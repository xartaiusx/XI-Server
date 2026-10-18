/*
===========================================================================

  Copyright (c) 2023 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#pragma once

#include "common/logging.h"
#include "common/settings.h"

#include <asio/ssl.hpp>
#include <cstdio>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>

#ifdef _WIN32
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <sddl.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace certificateHelpers
{

// Restrict access atomically at creation, never by chmod after writing a key.
// Existing paths (including links) are refused, and ownership passes to FILE.
inline auto openExclusivePrivateFile(const std::string& path) -> FILE*
{
#ifdef _WIN32
    const std::filesystem::path nativePath(path);
    PSECURITY_DESCRIPTOR        descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorA("D:P(A;;FA;;;OW)", SDDL_REVISION_1, &descriptor, nullptr))
    {
        return nullptr;
    }
    SECURITY_ATTRIBUTES attributes{ sizeof(SECURITY_ATTRIBUTES), descriptor, FALSE };
    // CREATE_NEW alone can follow a dangling link and create its target.
    const auto handle = CreateFileW(nativePath.c_str(), GENERIC_WRITE, 0, &attributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    LocalFree(descriptor);
    if (handle == INVALID_HANDLE_VALUE)
    {
        return nullptr;
    }
    DWORD flags = 0;
    if (!GetVolumeInformationByHandleW(handle, nullptr, 0, nullptr, nullptr, &flags, nullptr, 0) || (flags & FILE_PERSISTENT_ACLS) == 0)
    {
        CloseHandle(handle);
        return nullptr;
    }
    const int fd = _open_osfhandle(reinterpret_cast<intptr_t>(handle), _O_WRONLY | _O_BINARY | _O_NOINHERIT);
    if (fd == -1)
    {
        CloseHandle(handle);
        return nullptr;
    }
    FILE* file = _fdopen(fd, "wb");
    if (file == nullptr)
    {
        _close(fd);
    }
#else
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR);
    if (fd == -1)
    {
        return nullptr;
    }
    FILE* file = fdopen(fd, "wb");
    if (file == nullptr)
    {
        close(fd);
    }
#endif
    return file;
}

// Creates <name>.key and <name>.cert only when neither path exists.
inline void generateSelfSignedCert(const std::string& name = "login", const bool ellipticCurve = false)
{
    const auto keyFile   = name + ".key";
    const auto certFile  = name + ".cert";
    auto       closeFile = [](FILE* file) noexcept
    {
        fclose(file);
    };

    // symlink_status also detects dangling credential links. Never replace an
    // existing path or attempt to repair credential material during startup.
    const bool hasKey  = std::filesystem::exists(std::filesystem::symlink_status(keyFile));
    const bool hasCert = std::filesystem::exists(std::filesystem::symlink_status(certFile));

    if (hasKey || hasCert)
    {
        if (!hasKey || !hasCert || !std::filesystem::is_regular_file(keyFile) || !std::filesystem::is_regular_file(certFile))
        {
            throw std::runtime_error(fmt::format("Existing {} and {} must be a complete readable credential pair; no files were changed", keyFile, certFile));
        }

        const auto keyInput  = std::unique_ptr<FILE, decltype(closeFile)>(fopen(keyFile.c_str(), "rb"), closeFile);
        const auto certInput = std::unique_ptr<FILE, decltype(closeFile)>(fopen(certFile.c_str(), "rb"), closeFile);
        if (!keyInput || !certInput)
        {
            throw std::runtime_error(fmt::format("Cannot read existing {} and {}; no files were changed", keyFile, certFile));
        }

        // Unattended servers cannot answer an encrypted-key password prompt.
        const auto noPassword = [](char*, int, int, void*) -> int
        {
            return 0;
        };
        const auto pkey = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>(
            PEM_read_PrivateKey(keyInput.get(), nullptr, noPassword, nullptr), EVP_PKEY_free);
        const auto cert = std::unique_ptr<X509, decltype(&X509_free)>(
            PEM_read_X509(certInput.get(), nullptr, nullptr, nullptr), X509_free);
        if (!pkey || !cert || X509_check_private_key(cert.get(), pkey.get()) != 1)
        {
            throw std::runtime_error(fmt::format("Existing {} and {} must contain matching readable PEM credentials; no files were changed", keyFile, certFile));
        }

        ShowInfoFmt("Found existing {} and {}", keyFile, certFile);
        if (X509_cmp_time(X509_get_notAfter(cert.get()), nullptr) != 1 || X509_cmp_time(X509_get_notBefore(cert.get()), nullptr) != -1)
        {
            ShowWarningFmt("Existing {} is not valid for the current time. Obtain a replacement explicitly.", certFile);
        }
        return;
    }

    ShowInfo("Generating self-signed certificate");

    const auto pkey = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>(
        ellipticCurve ? EVP_EC_gen("P-256") : EVP_RSA_gen(4096), EVP_PKEY_free);
    if (!pkey)
    {
        throw std::runtime_error("Failed to generate private key");
    }

    const auto x509 = std::unique_ptr<X509, decltype(&X509_free)>(X509_new(), X509_free);
    if (!x509)
    {
        throw std::runtime_error("Failed to allocate X509 certificate");
    }

    if (!ASN1_INTEGER_set(X509_get_serialNumber(x509.get()), 1) ||
        !X509_gmtime_adj(X509_get_notBefore(x509.get()), 0) ||
        !X509_gmtime_adj(X509_get_notAfter(x509.get()), 31536000L * 20) ||
        !X509_set_pubkey(x509.get(), pkey.get()))
    {
        throw std::runtime_error("Failed to initialize X509 certificate");
    }

    X509_NAME* subject = X509_get_subject_name(x509.get());

    std::string   authIpAddr           = settings::get<std::string>("network.LOGIN_AUTH_IP");
    unsigned char commonNameIpAddr[17] = {}; // size of "255.255.255.255\0"

    authIpAddr.copy(reinterpret_cast<char*>(commonNameIpAddr), sizeof(commonNameIpAddr) - 1);

    const auto organization = fmt::format("Mochirii self-signed certificate for {} server", name);
    if (!X509_NAME_add_entry_by_txt(subject, "O", MBSTRING_ASC, reinterpret_cast<const unsigned char*>(organization.c_str()), -1, -1, 0) ||
        !X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, commonNameIpAddr, -1, -1, 0) ||
        !X509_set_issuer_name(x509.get(), subject) ||
        !X509_sign(x509.get(), pkey.get(), EVP_sha384()))
    {
        throw std::runtime_error("Failed to sign X509 certificate");
    }

    // Exclusive creation also refuses paths introduced after the checks above.
    auto keyOutput = std::unique_ptr<FILE, decltype(closeFile)>(openExclusivePrivateFile(keyFile), closeFile);
    if (!keyOutput || PEM_write_PrivateKey(keyOutput.get(), pkey.get(), nullptr, nullptr, 0, nullptr, nullptr) != 1)
    {
        throw std::runtime_error(fmt::format("Failed to create {}; existing paths were not replaced", keyFile));
    }
    if (fclose(keyOutput.release()) != 0)
    {
        throw std::runtime_error(fmt::format("Failed to close {}", keyFile));
    }

    auto certOutput = std::unique_ptr<FILE, decltype(closeFile)>(openExclusivePrivateFile(certFile), closeFile);
    if (!certOutput || PEM_write_X509(certOutput.get(), x509.get()) != 1)
    {
        throw std::runtime_error(fmt::format("Failed to create {}; existing paths were not replaced", certFile));
    }
    if (fclose(certOutput.release()) != 0)
    {
        throw std::runtime_error(fmt::format("Failed to close {}", certFile));
    }
}

} // namespace certificateHelpers
