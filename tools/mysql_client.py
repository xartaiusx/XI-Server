"""Bounded native MariaDB calls without connection credentials in argv or env."""

import contextlib
import ctypes
import errno
import argparse
import hmac
import math
import ntpath
import os
import pathlib
import re
import stat
import subprocess
import sys

MAX_OPTIONS_BYTES = 16384
MAX_FIELD_BYTES = 4096
OPTIONS_FILE_ENV = "MOCHIRII_MYSQL_OPTIONS_FILE"
CANONICAL_CNF = "/mnt/c/Github Repo's/FFXI/FFXI Creds/Server/mariadb-client.cnf"


class MySQLClientError(RuntimeError):
    """A deliberately redacted native-client or credential preflight failure."""


def serialize_options(host, user, port, password):
    """Return the sole accepted [client] format; never log the returned bytes."""

    def quote(value):
        if not isinstance(value, str) or "\0" in value:
            raise MySQLClientError("Invalid native database connection configuration.")
        if len(value.encode("utf-8")) > MAX_FIELD_BYTES:
            raise MySQLClientError("Invalid native database connection configuration.")
        for before, after in (
            ("\\", "\\\\"),
            ('"', '\\"'),
            ("\n", "\\n"),
            ("\r", "\\r"),
            ("\t", "\\t"),
            ("\b", "\\b"),
        ):
            value = value.replace(before, after)
        return '"' + value + '"'

    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise MySQLClientError("Invalid native database connection configuration.")
    if not host or not user:
        raise MySQLClientError("Invalid native database connection configuration.")
    result = (
        f"[client]\nhost={quote(host)}\nport={port}\n"
        f"user={quote(user)}\npassword={quote(password)}\n"
    ).encode("utf-8")
    if len(result) > MAX_OPTIONS_BYTES:
        raise MySQLClientError("Invalid native database connection configuration.")
    return result


def _child_environment():
    # Clear both the project's password input and native clients' password inputs.
    connection_keys = {
        "XI_NETWORK_SQL_HOST",
        "XI_NETWORK_SQL_PORT",
        "XI_NETWORK_SQL_LOGIN",
        "MYSQL_HOST",
        "MYSQL_TCP_PORT",
        "MYSQL_USER",
        "MYSQL_PWD",
        "MYSQL_TEST_LOGIN_FILE",
        "MARIADB_HOST",
        "MARIADB_PORT",
        "MARIADB_USER",
        "MARIADB_PWD",
    }
    environment = {
        key: value
        for key, value in os.environ.items()
        if "PASSWORD" not in key.upper()
        and not key.upper().endswith("_PWD")
        and key.upper() not in connection_keys
    }
    # MySQL reads login paths even with --defaults-file; MariaDB ignores this input.
    # A drive-root DOS device survives MySQL's dot-component path normalization.
    if sys.platform == "win32":
        drive, remainder = ntpath.splitdrive(_windows_powershell())
        if not re.fullmatch(r"[A-Za-z]:", drive) or not remainder.startswith(
            ("\\", "/")
        ):
            raise MySQLClientError("Windows null-device isolation is unavailable.")
        environment["MYSQL_TEST_LOGIN_FILE"] = drive + r"\NUL"
    else:
        environment["MYSQL_TEST_LOGIN_FILE"] = "/dev/null"
    return environment


def _check_darwin_acl(fd):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.acl_get_fd_np.argtypes = (ctypes.c_int, ctypes.c_int)
    libc.acl_get_fd_np.restype = ctypes.c_void_p
    libc.acl_get_entry.argtypes = (
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_void_p),
    )
    libc.acl_get_entry.restype = ctypes.c_int
    libc.acl_valid.argtypes = (ctypes.c_void_p,)
    libc.acl_valid.restype = ctypes.c_int
    libc.acl_free.argtypes = (ctypes.c_void_p,)
    libc.acl_free.restype = ctypes.c_int
    ctypes.set_errno(0)
    acl = libc.acl_get_fd_np(fd, 0x100)  # Darwin ACL_TYPE_EXTENDED.
    if not acl:
        if ctypes.get_errno() == errno.ENOENT:  # FILESEC_ACL is absent.
            return
        raise MySQLClientError("Private database option-file validation failed.")
    try:
        if libc.acl_valid(acl) != 0:
            raise MySQLClientError("Private database option-file validation failed.")
        entry = ctypes.c_void_p()
        ctypes.set_errno(0)
        result = libc.acl_get_entry(acl, 0, ctypes.byref(entry))  # ACL_FIRST_ENTRY.
        if result != -1 or ctypes.get_errno() != errno.EINVAL:
            raise MySQLClientError("Private database option-file validation failed.")
    finally:
        libc.acl_free(acl)


def _check_posix_object(fd, directory=False):
    info = os.fstat(fd)
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    mode = stat.S_IMODE(info.st_mode)
    allowed_modes = (0o500, 0o700) if directory else (0o400, 0o600)
    if (
        not expected(info.st_mode)
        or info.st_uid != os.geteuid()
        or mode not in allowed_modes
    ):
        raise MySQLClientError("Private database option-file validation failed.")
    if sys.platform == "darwin":
        _check_darwin_acl(fd)


@contextlib.contextmanager
def _existing_options(path, expected):
    candidate = pathlib.Path(path)
    if not candidate.is_absolute() or (
        sys.platform == "win32" and str(candidate).startswith(("\\\\", "//"))
    ):
        raise MySQLClientError("Private database option-file validation failed.")
    with contextlib.ExitStack() as stack:
        if sys.platform == "win32":
            _check_windows_privacy(candidate)
            fd = os.open(candidate, os.O_RDONLY | getattr(os, "O_BINARY"))
        elif sys.platform == "darwin":
            parent = os.open(
                candidate.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            )
            stack.callback(os.close, parent)
            _check_posix_object(parent, directory=True)
            fd = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        else:
            raise MySQLClientError("Secure native database transport is unavailable.")
        stack.callback(os.close, fd)
        if sys.platform != "win32":
            _check_posix_object(fd)
        info = os.fstat(fd)
        if not 0 < info.st_size <= MAX_OPTIONS_BYTES:
            raise MySQLClientError("Private database option-file validation failed.")
        content = os.read(fd, MAX_OPTIONS_BYTES + 1)
        if (
            any(
                line.lstrip().lower().startswith(b"!include")
                for line in content.splitlines()
            )
            or len(content) != info.st_size
            or not hmac.compare_digest(content, expected)
        ):
            raise MySQLClientError("Private database option-file validation failed.")
        yield str(candidate)


@contextlib.contextmanager
def _options_source(content, options_file):
    if sys.platform.startswith("linux"):
        if not hasattr(os, "memfd_create") or not hasattr(os, "MFD_CLOEXEC"):
            raise MySQLClientError("Secure native database transport is unavailable.")
        fd = os.memfd_create("mochirii-mysql-options", os.MFD_CLOEXEC)
        try:
            os.fchmod(fd, 0o600)
            written = 0
            while written < len(content):
                count = os.write(fd, content[written:])
                if count <= 0:
                    raise MySQLClientError("Secure native database transport failed.")
                written += count
            os.lseek(fd, 0, os.SEEK_SET)
            yield f"/proc/self/fd/{fd}", (fd,)
        finally:
            os.close(fd)
    else:
        path = options_file or os.environ.get(OPTIONS_FILE_ENV)
        if not path:
            raise MySQLClientError(
                "A pre-existing private database option file is required."
            )
        with _existing_options(path, content) as validated_path:
            yield validated_path, ()


def run_mysql(
    executable,
    arguments,
    *,
    host,
    user,
    port,
    password,
    options_file=None,
    timeout=600,
    capture_output=True,
):
    """Run a native client with bounded lifetime and redacted failure diagnostics."""
    try:
        if (
            isinstance(timeout, bool)
            or not isinstance(timeout, (int, float))
            or not math.isfinite(timeout)
            or not 0 < timeout <= 3600
        ):
            raise MySQLClientError("Invalid native database client timeout.")
        _validate_arguments(arguments)
        content = serialize_options(host, user, port, password)
        with _options_source(content, options_file) as (path, descriptors):
            kwargs = {
                "stdout": subprocess.PIPE if capture_output else None,
                "stderr": subprocess.PIPE,
                "text": True,
                "timeout": timeout,
                "check": False,
                "env": _child_environment(),
                "close_fds": True,
            }
            if descriptors:
                kwargs["pass_fds"] = descriptors
            result = subprocess.run(
                [executable, f"--defaults-file={path}", *arguments], **kwargs
            )
            # Native errors may echo credentials or source SQL. Never forward them.
            result.stderr = (
                "Native database command failed." if result.returncode else ""
            )
            if result.returncode:
                result.stdout = ""
            return result
    except MySQLClientError:
        raise
    except (OSError, ValueError, TypeError, AttributeError, subprocess.SubprocessError):
        raise MySQLClientError("Secure native database command failed.") from None


def _parse_client_options(content):
    """Accept a small, unambiguous MariaDB [client] subset without includes."""
    if not 0 < len(content) <= MAX_OPTIONS_BYTES or b"\0" in content:
        raise MySQLClientError("Private database option-file validation failed.")
    section_seen = False
    values = {}
    escapes = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "b": "\b",
        "s": " ",
        "\\": "\\",
        '"': '"',
        "'": "'",
    }
    for line in content.decode("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line == "[client]" and not section_seen:
            section_seen = True
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if (
            not section_seen
            or not separator
            or key not in ("host", "user", "port", "password")
            or key in values
            or line.startswith("!")
        ):
            raise MySQLClientError("Private database option-file validation failed.")
        quote = value[0] if value.startswith(('"', "'")) else None
        if quote:
            if len(value) < 2 or value[-1] != value[0]:
                raise MySQLClientError(
                    "Private database option-file validation failed."
                )
            value = value[1:-1]
        decoded = []
        index = 0
        while index < len(value):
            character = value[index]
            if character == "\\":
                index += 1
                if index >= len(value) or value[index] not in escapes:
                    raise MySQLClientError(
                        "Private database option-file validation failed."
                    )
                character = escapes[value[index]]
            elif quote and character == quote:
                raise MySQLClientError(
                    "Private database option-file validation failed."
                )
            decoded.append(character)
            index += 1
        values[key] = "".join(decoded)
    if not section_seen or "user" not in values or "password" not in values:
        raise MySQLClientError("Private database option-file validation failed.")
    connection = {
        "host": values.get("host", "127.0.0.1"),
        "user": values["user"],
        "port": int(values.get("port", "3306")),
        "password": values["password"],
    }
    serialize_options(**connection)
    return connection


def _read_private_linux_options(path):
    candidate = pathlib.Path(path)
    if not candidate.is_absolute():
        raise MySQLClientError("Private database option-file validation failed.")
    if str(candidate) == CANONICAL_CNF:
        _check_canonical_windows_acl()
    with contextlib.ExitStack() as stack:
        fd = os.open(candidate, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        stack.callback(os.close, fd)
        if str(candidate) != CANONICAL_CNF:
            _check_posix_object(fd)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= MAX_OPTIONS_BYTES:
            raise MySQLClientError("Private database option-file validation failed.")
        content = os.read(fd, MAX_OPTIONS_BYTES + 1)
        if len(content) != info.st_size:
            raise MySQLClientError("Private database option-file validation failed.")
        connection = _parse_client_options(content)
        if (
            connection["host"] not in ("127.0.0.1", "localhost")
            or connection["port"] != 3306
        ):
            raise MySQLClientError(
                "Canonical database controls require the local database."
            )
        connection["host"] = "127.0.0.1"
        return connection


def _check_canonical_windows_acl():
    _check_windows_privacy()


def _windows_powershell():
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.GetSystemDirectoryW.argtypes = (ctypes.c_wchar_p, ctypes.c_uint)
    kernel.GetSystemDirectoryW.restype = ctypes.c_uint
    directory = ctypes.create_unicode_buffer(32768)
    length = kernel.GetSystemDirectoryW(directory, len(directory))
    if not 0 < length < len(directory):
        raise MySQLClientError("Windows metadata validation is unavailable.")
    return str(pathlib.Path(directory.value) / "WindowsPowerShell/v1.0/powershell.exe")


def _check_windows_privacy(path=None):
    # DrvFS mode bits do not describe the original NTFS confidentiality boundary.
    # Static, exact-path, metadata-only check; never emit identities or contents.
    script = r"""
$ErrorActionPreference = 'Stop'
try {
  Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1" -ErrorAction Stop
  Import-Module "$PSHOME\Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1" -ErrorAction Stop
  $canonical = [string]::IsNullOrEmpty($env:MOCHIRII_PRIVATE_OPTION_PATH)
  $path = if ($canonical) { 'C:\Github Repo''s\FFXI\FFXI Creds\Server\mariadb-client.cnf' } else { $env:MOCHIRII_PRIVATE_OPTION_PATH }
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $trusted = @($sid, 'S-1-5-18', 'S-1-5-32-544')
  $paths = @($path, [System.IO.Path]::GetDirectoryName($path))
  for ($index = 0; $index -lt $paths.Count; $index++) {
    $item = Get-Item -LiteralPath $paths[$index] -Force
    $acl = Get-Acl -LiteralPath $paths[$index]
    $raw = [System.Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorBinaryForm(), 0)
    $valid = -not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -and ($item.PSIsContainer -eq ($index -eq 1))
    $valid = $valid -and ($null -ne $raw.DiscretionaryAcl) -and $raw.DiscretionaryAcl.Count -gt 0
    if ($canonical) {
      $valid = $valid -and $trusted.Contains($raw.Owner.Value)
      foreach ($rule in $acl.Access) {
        $untrustedAllow = $rule.AccessControlType -eq 'Allow' -and -not $trusted.Contains($rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value)
        if ($untrustedAllow -and ($index -eq 0 -or ($rule.FileSystemRights -band 0x500D0156))) { $valid = $false }
      }
    } else {
      $valid = $valid -and ($raw.Owner.Value -eq $sid) -and $acl.AreAccessRulesProtected
      foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceType -ne 'AccessAllowed' -or $ace.AceFlags -ne 'None' -or $ace.SecurityIdentifier.Value -ne $sid) { $valid = $false }
      }
    }
    if (-not $valid) { exit 1 }
  }
  [Console]::Out.Write('private')
} catch { exit 1 }
"""
    environment = _child_environment()
    environment.pop("MOCHIRII_PRIVATE_OPTION_PATH", None)
    if path is not None:
        environment["MOCHIRII_PRIVATE_OPTION_PATH"] = str(path)
    powershell = (
        _windows_powershell()
        if path is not None
        else "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    )
    result = subprocess.run(
        [
            powershell,
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script,
        ],
        capture_output=True,
        timeout=30,
        check=False,
        env=environment,
    )
    if result.returncode or result.stdout != b"private":
        raise MySQLClientError("Canonical database credential ACL validation failed.")


def _validate_arguments(arguments):
    """Only caller-required shapes; MariaDB option abbreviations are forbidden."""
    if not isinstance(arguments, (list, tuple)) or len(arguments) > 3:
        raise MySQLClientError("Invalid native database arguments.")
    for argument in arguments:
        if (
            not isinstance(argument, str)
            or "\0" in argument
            or len(argument.encode("utf-8")) > 1048576
        ):
            raise MySQLClientError("Invalid native database arguments.")
    values = list(arguments)
    if values == ["--version"]:  # Public program version; no connection is opened.
        return
    if values and not values[0].startswith("-"):
        database = values.pop(0)
        if not re.fullmatch(r"[A-Za-z0-9_]{1,64}", database):
            raise MySQLClientError("Invalid public database identifier.")
    if values and (len(values) != 2 or values[0] not in ("-e", "--execute")):
        raise MySQLClientError("Unsupported native database options.")


def main(argv=None):
    """Canonical Linux controls: private existing CNF -> memory-only native call."""
    parser = argparse.ArgumentParser(
        description="Credential-safe native MariaDB control."
    )
    parser.add_argument("--credential-file", default=CANONICAL_CNF)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        if not sys.platform.startswith("linux"):
            raise MySQLClientError(
                "Canonical database controls require Linux memfd support."
            )
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not args.check and (
            not command
            or command[0]
            not in (
                "mysql",
                "mariadb",
            )
        ):
            raise MySQLClientError("Unsupported native database command.")
        if command:
            _validate_arguments(command[1:])
        connection = _read_private_linux_options(args.credential_file)
        if args.check:
            with _options_source(serialize_options(**connection), None):
                return 0
        result = run_mysql(command[0], command[1:], **connection, capture_output=False)
        if result.returncode:
            raise MySQLClientError("Native database command failed.")
        return 0
    except (
        MySQLClientError,
        OSError,
        ValueError,
        TypeError,
        subprocess.SubprocessError,
    ):
        print(
            "Secure database control failed; connection details are withheld.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
