"""One hosted synthetic ASAN observation; only encrypted evidence may leave it."""

import base64
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import time
import traceback
from types import SimpleNamespace

REPOSITORY = "xartaiusx/XI-Server"
PROGRAM = "75ef2a9b1eb5f74ce1a5b7a5e6bd6c6f557f7483"
REF = "refs/heads/mochi/hosted-asan-stdout-reader-20261023"
NONCE = "ea17616a5f424077ab04370da9553bab"
LIMIT = 128 * 1024 * 1024
LOG_LIMIT = 64 * 1024 * 1024


def require(condition):
    if not condition:
        raise RuntimeError("Hosted diagnostic contract failed")


def unique(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value)
        value[key] = item
    return value


def encode(value):
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n"
    ).encode()


def private_file(path, content):
    descriptor = os.open(
        path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def regular(path, maximum):
    info = path.lstat()
    require(
        stat.S_ISREG(info.st_mode)
        and info.st_nlink == 1
        and 0 < info.st_size <= maximum
    )
    return info


def stable(info):
    return tuple(
        getattr(info, field)
        for field in (
            "st_dev",
            "st_ino",
            "st_mode",
            "st_nlink",
            "st_uid",
            "st_gid",
            "st_size",
            "st_mtime_ns",
            "st_ctime_ns",
        )
    )


def public_context(env, controller):
    required = {
        "GITHUB_REPOSITORY": REPOSITORY,
        "GITHUB_EVENT_NAME": "workflow_dispatch",
        "GITHUB_ACTOR": "xartaiusx",
        "GITHUB_TRIGGERING_ACTOR": "xartaiusx",
        "GITHUB_REF": REF,
        "GITHUB_RUN_ATTEMPT": "1",
        "RUNNER_ENVIRONMENT": "github-hosted",
        "RUNNER_OS": "Linux",
        "RUNNER_ARCH": "X64",
        "DIAGNOSTIC_REQUEST_NONCE": NONCE,
        "DIAGNOSTIC_ENABLED": "true",
    }
    require(all(env.get(key) == value for key, value in required.items()))
    require(env.get("RUNNER_DEBUG", "0") != "1")
    require(env.get("ACTIONS_STEP_DEBUG", "false").lower() != "true")
    head = env["DIAGNOSTIC_EXPECTED_HEAD"]
    require(
        re.fullmatch(r"[0-9a-f]{40}", head) is not None and env["GITHUB_SHA"] == head
    )
    require(env["DIAGNOSTIC_WORKFLOW_HEAD"] == head)
    require(re.fullmatch(r"[1-9][0-9]{0,14}", env["GITHUB_RUN_ID"]) is not None)
    workflow = controller / ".github/workflows/sanitizers.yml"
    regular(workflow, 65536)
    workflow_hash = hashlib.sha256(workflow.read_bytes()).hexdigest()
    require(workflow_hash == env["DIAGNOSTIC_WORKFLOW_SHA256"])
    require(1 <= len(env["DIAGNOSTIC_RECIPIENT_SPKI"]) <= 2048)
    public = base64.b64decode(env["DIAGNOSTIC_RECIPIENT_SPKI"], validate=True)
    require(512 <= len(public) <= 1024)
    recipient_hash = hashlib.sha256(public).hexdigest()
    require(recipient_hash == env["DIAGNOSTIC_RECIPIENT_SHA256"])
    return {
        "schema": "mochirii-hosted-asan-evidence-v1",
        "repository": REPOSITORY,
        "source_head": head,
        "program_baseline": PROGRAM,
        "workflow_sha256": workflow_hash,
        "run_id": int(env["GITHUB_RUN_ID"]),
        "run_attempt": 1,
        "request_nonce": NONCE,
        "recipient_sha256": recipient_hash,
        "diagnostic_only": True,
        "acceptance": False,
    }, public


def child_environment(env):
    names = {
        "PATH",
        "HOME",
        "USER",
        "LOGNAME",
        "LANG",
        "LC_ALL",
        "TMPDIR",
        "LD_LIBRARY_PATH",
        "LIBRARY_PATH",
        "PKG_CONFIG_PATH",
        "CMAKE_PREFIX_PATH",
    }
    value = {key: item for key, item in env.items() if key in names}
    value.update(CI="true", PYTHONDONTWRITEBYTECODE="1", PYTHONNOUSERSITE="1")
    return value


def command_runner(ctx):
    used = set()

    def run(label, argv, *, cwd, timeout, env=None, check=True, capture=False):
        require(
            re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", label) is not None
            and label not in used
        )
        require(
            isinstance(argv, list)
            and argv
            and all(isinstance(x, str) and "\0" not in x for x in argv)
        )
        require(type(timeout) is int and 1 <= timeout <= 5400)
        effective_env = ctx.env if env is None else env
        require(
            not any(
                key.startswith(("GITHUB_", "GH_", "ACTIONS_")) for key in effective_env
            )
        )
        used.add(label)
        log_limit = 32 * 1024 * 1024 if label == "one-native-observation" else LOG_LIMIT
        log = ctx.evidence / (label + ".log")
        descriptor = os.open(
            log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
        )
        process = None
        with os.fdopen(descriptor, "wb") as stream:
            try:
                process = subprocess.Popen(
                    argv,
                    cwd=cwd,
                    env=effective_env,
                    stdin=subprocess.DEVNULL,
                    stdout=stream,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                deadline = time.monotonic() + timeout
                while process.poll() is None:
                    require(
                        log.stat().st_size <= log_limit and time.monotonic() < deadline
                    )
                    time.sleep(0.2)
                code = process.wait(timeout=5)
            finally:
                if process is not None and process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=10)
        require(log.stat().st_size <= log_limit)
        data = b""
        if capture:
            require(log.stat().st_size <= 1024 * 1024)
            data = log.read_bytes()
        if check:
            require(code == 0)
        return {"returncode": code, "log": log, "stdout": data}

    return run


def load_builder(controller):
    path = controller / ".github/scripts/hosted_asan_sql.py"
    regular(path, 262144)
    spec = importlib.util.spec_from_file_location("hosted_asan_sql", path)
    require(spec is not None and spec.loader is not None)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def package_evidence(ctx):
    paths = sorted(ctx.evidence.rglob("*"))
    require(0 < len(paths) <= 256)
    files, total = [], 0
    for path in paths:
        info = path.lstat()
        if stat.S_ISDIR(info.st_mode):
            continue
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_nlink == 1
            and info.st_size <= LOG_LIMIT
        )
        require(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o600)
        relative = path.relative_to(ctx.evidence).as_posix()
        require(
            all(
                re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", part)
                for part in relative.split("/")
            )
        )
        total += info.st_size
        require(total <= LIMIT)
        files.append((path, relative, info))
    target = ctx.work / "private-evidence.tar.gz"
    descriptor = os.open(
        target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
    )
    with os.fdopen(descriptor, "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w|") as archive:
                for path, relative, info in files:
                    entry = tarfile.TarInfo(relative)
                    entry.size, entry.mode, entry.mtime = info.st_size, 0o600, 0
                    descriptor = os.open(
                        path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                    )
                    with os.fdopen(descriptor, "rb") as source:
                        require(stable(os.fstat(source.fileno())) == stable(info))
                        archive.addfile(entry, source)
                        require(stable(os.fstat(source.fileno())) == stable(info))
    regular(target, LIMIT)
    return target


def output_ready(path):
    require(path.is_absolute() and path.is_file() and not path.is_symlink())
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "a", encoding="ascii") as stream:
        stream.write("ciphertext_ready=true\n")


def main():
    os.umask(0o077)
    require(sys.platform.startswith("linux"))
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    require(workspace.is_absolute() and workspace == workspace.resolve(strict=True))
    controller, program = workspace / "diagnostic", workspace / "program"
    require(
        controller == controller.resolve(strict=True)
        and program == program.resolve(strict=True)
    )
    require(
        Path(__file__).resolve()
        == controller / ".github/scripts/hosted_asan_private.py"
    )
    context, recipient = public_context(os.environ, controller)
    temp = Path(os.environ["RUNNER_TEMP"])
    require(temp.is_absolute() and temp == temp.resolve(strict=True))
    work = temp / ("mochirii-asan-" + NONCE)
    work.mkdir(mode=0o700)
    evidence, sealed = work / "evidence", work / "sealed"
    evidence.mkdir(mode=0o700)
    sealed.mkdir(mode=0o700)
    ctx = SimpleNamespace(
        work=work,
        evidence=evidence,
        program=program,
        controller=controller,
        env=child_environment(os.environ),
        nonce=NONCE,
        request_nonce=NONCE,
        source=PROGRAM,
        expected_cpp=103,
        expected_executed=1,
        expected_filtered=19,
    )
    run = command_runner(ctx)
    public_path, context_path = work / "recipient.spki.der", work / "context.json"
    private_file(public_path, recipient)
    private_file(context_path, encode(context))
    private_file(evidence / "context.json", encode(context))
    outcome = {
        "diagnostic_only": True,
        "acceptance": False,
        "completed": False,
        "phase": "preflight",
    }
    result, encrypted = 1, False
    try:
        require(shutil.which("pwsh") is not None)
        crypto = controller / ".github/scripts/hosted_asan_evidence.ps1"
        regular(crypto, 262144)
        for label, directory, expected in (
            ("controller_head", controller, context["source_head"]),
            ("program_head", program, PROGRAM),
        ):
            actual = run(
                label,
                ["git", "--no-optional-locks", "rev-parse", "HEAD"],
                cwd=directory,
                timeout=30,
                capture=True,
            )
            require(actual["stdout"].decode().strip() == expected)
            status = run(
                label + "_clean",
                [
                    "git",
                    "--no-optional-locks",
                    "status",
                    "--porcelain",
                    "--untracked-files=all",
                ],
                cwd=directory,
                timeout=30,
                capture=True,
            )
            require(not status["stdout"].strip())
        probe = work / "crypto-probe.txt"
        private_file(
            probe, b"Synthetic cryptographic preflight only; no native test.\n"
        )
        run(
            "encryption_preflight",
            [
                "pwsh",
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-File",
                str(crypto),
                "-Mode",
                "Encrypt",
                "-ArchivePath",
                str(probe),
                "-PublicSpkiPath",
                str(public_path),
                "-ContextPath",
                str(context_path),
                "-CiphertextPath",
                str(work / "crypto-probe.bin"),
            ],
            cwd=controller,
            timeout=60,
        )
        regular(work / "crypto-probe.bin", 65536)
        builder = load_builder(controller)
        outcome["phase"] = "build"
        outcome["build"] = builder.stage_and_build(ctx, run)
        outcome["phase"] = "observation"
        # Exactly one native child; both this guard and the builder guard are exclusive.
        private_file(evidence / "observation.authorization.json", encode(context))
        outcome["observation"] = builder.observe_once(ctx, run)
        outcome["completed"] = True
        outcome["phase"] = "finished"
        require(outcome["observation"].get("passed") is True)
        result = 0
    except BaseException:
        private_file(
            evidence / "private-exception.txt", traceback.format_exc().encode()
        )
    finally:
        private_file(evidence / "outcome.json", encode(outcome))
        try:
            archive = package_evidence(ctx)
            run(
                "encrypt_evidence",
                [
                    "pwsh",
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-File",
                    str(crypto),
                    "-Mode",
                    "Encrypt",
                    "-ArchivePath",
                    str(archive),
                    "-PublicSpkiPath",
                    str(public_path),
                    "-ContextPath",
                    str(context_path),
                    "-CiphertextPath",
                    str(sealed / "evidence.bin"),
                ],
                cwd=controller,
                timeout=120,
            )
            regular(sealed / "evidence.bin", LIMIT + 16384)
            output_ready(Path(os.environ["GITHUB_OUTPUT"]))
            encrypted = True
        except BaseException:
            result = 1
    print(
        json.dumps(
            {
                "diagnostic_only": True,
                "acceptance": False,
                "encrypted_evidence_ready": encrypted,
            }
        )
    )
    return result


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        raise SystemExit(
            "Hosted diagnostic blocked; no plaintext evidence was published."
        ) from None
