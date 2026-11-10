"""Seed the exact public release bytes needed by CI configuration and LuaLS."""

from hashlib import sha256
from http.client import HTTPException
from pathlib import Path
import os
import platform
from secrets import token_hex
import signal
import stat
import sys
from urllib.error import HTTPError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

RELEASES = {
    "cpm": (
        "cpm-cmake/CPM.cmake",
        "v0.40.2",
        "CPM.cmake",
        183458005,
        41017,
        "c8cdc32c03816538ce22781ed72964dc864b2a34a310d3b7104812a5ca2d835d",
    ),
    "luals": (
        "LuaLS/lua-language-server",
        "3.19.2",
        "lua-language-server-3.19.2-linux-x64.tar.gz",
        635856120,
        3696210,
        "93ad326b10f6c00911dd8c450fa098332dbd8f9f45d1052f5636a2d54479b947",
    ),
}


class NoReleaseRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def download_timeout(_signum, _frame):
    raise TimeoutError("Release download exceeded its time limit")


def open_release(opener, url):
    for _ in range(5):
        target = urlsplit(url)
        if (
            target.scheme != "https"
            or target.hostname
            not in {
                "github.com",
                "api.github.com",
                "release-assets.githubusercontent.com",
                "objects.githubusercontent.com",
            }
            or target.username is not None
            or target.password is not None
            or target.port not in (None, 443)
        ):
            raise OSError("Unexpected release URL")

        request = Request(url, headers={"Accept": "application/octet-stream"})
        try:
            return opener.open(request, timeout=10)
        except HTTPError as error:
            # Do not drain an untrusted redirect or error response body.
            with error:
                location = error.headers.get("Location")
                if error.code not in (301, 302, 303, 307, 308) or not location:
                    raise
            url = urljoin(url, location)
    raise OSError("Too many release redirects")


def download(url, size):
    # This standalone Linux CI command has no other use of SIGALRM.
    old_handler = signal.signal(signal.SIGALRM, download_timeout)
    signal.setitimer(signal.ITIMER_REAL, 45)
    try:
        opener = build_opener(NoReleaseRedirects())
        with open_release(opener, url) as response:
            data = bytearray()
            while len(data) <= size:
                chunk = response.read1(min(65536, size + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
        if len(data) > size:
            raise OSError("Release download exceeded its byte limit")
        return data
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old_handler)


def open_parent(workspace, destination):
    if not workspace.is_absolute() or workspace.resolve(strict=True) != workspace:
        raise OSError("Expected a real absolute GITHUB_WORKSPACE")
    relative = destination.relative_to(workspace)
    if not relative.parts or ".." in relative.parts:
        raise OSError("Release destination is outside GITHUB_WORKSPACE")

    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(workspace, flags)
    try:
        for part in relative.parts[:-1]:
            try:
                child = os.open(part, flags, dir_fd=fd)
            except FileNotFoundError:
                os.mkdir(part, dir_fd=fd)
                child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd, relative.name
    except BaseException:
        os.close(fd)
        raise


def regular_target(directory, name):
    try:
        entry = os.stat(name, dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        return False
    if not stat.S_ISREG(entry.st_mode):
        raise OSError("Release destination is not a regular file")
    return True


def seed_release(tool, workspace, destination):
    repository, tag, asset, asset_id, size, digest = RELEASES[tool]
    directory, name = open_parent(workspace, destination)
    try:
        if regular_target(directory, name):
            flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
            with os.fdopen(os.open(name, flags, dir_fd=directory), "rb") as existing:
                info = os.fstat(existing.fileno())
                if not stat.S_ISREG(info.st_mode):
                    raise OSError("Release destination is not a regular file")
                if (
                    info.st_size == size
                    and sha256(existing.read(size + 1)).hexdigest() == digest
                ):
                    return

        urls = (
            f"https://github.com/{repository}/releases/download/{tag}/{asset}",
            f"https://api.github.com/repos/{repository}/releases/assets/{asset_id}?download=1",
        )
        for url in urls:
            try:
                data = download(url, size)
            except (OSError, HTTPException):
                continue
            if len(data) == size and sha256(data).hexdigest() == digest:
                break
        else:
            raise SystemExit(
                f"Could not obtain the SHA-256 verified {tool} release asset"
            )

        temporary = f".{name}.{token_hex(8)}.tmp"
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        fd = os.open(temporary, flags, 0o600, dir_fd=directory)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            regular_target(directory, name)
            os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        finally:
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass
    finally:
        os.close(directory)


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in RELEASES:
        raise SystemExit("Usage: fetch_pinned_release.py cpm|luals")

    tool = sys.argv[1]
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    if tool == "cpm":
        target = Path(os.environ["CPM_SOURCE_CACHE"]) / "cpm/CPM_0.40.2.cmake"
    else:
        if platform.system() != "Linux" or platform.machine() != "x86_64":
            raise SystemExit("The pinned Lua Language Server asset requires Linux x64")
        target = workspace / "lua-language-server.linux-x64.tar.gz"

    seed_release(tool, workspace, target)
