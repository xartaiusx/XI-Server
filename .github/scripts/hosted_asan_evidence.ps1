# Public-source proposal. Loading Library mode performs no I/O or key generation.
[CmdletBinding()]
param(
    [ValidateSet('Library', 'Encrypt')][string]$Mode = 'Library',
    [string]$ArchivePath,
    [string]$PublicSpkiPath,
    [string]$ContextPath,
    [string]$CiphertextPath
)

function Initialize-HostedAsanCrypto {
    if ('Mochirii.HostedAsanEvidenceV1' -as [type]) { return }
    Add-Type -Language CSharp -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace Mochirii
{
    public static class HostedAsanEvidenceV1
    {
        public const int MaxPayload = 128 * 1024 * 1024;
        public const int MaxHeader = 8192;
        public const int MaxEnvelope = MaxPayload + MaxHeader + 35;
        public const string RequestNonce = "4bbc0bb9dc7b4cb7ac767ff2376e3750";
        public const string ProgramBaseline = "75ef2a9b1eb5f74ce1a5b7a5e6bd6c6f557f7483";
        public const string Schema = "mochirii-hosted-asan-evidence-v1";
        private const string Algorithm = "RSA4096-OAEP-SHA256+AES256-GCM";
        private static readonly byte[] Magic = Encoding.ASCII.GetBytes("MOCHI-ASAN-EV1\n");
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        private static readonly string[] ContextNames = {
            "schema", "repository", "source_head", "program_baseline", "workflow_sha256",
            "run_id", "run_attempt", "request_nonce", "recipient_sha256", "diagnostic_only", "acceptance"
        };
        private static readonly string[] HeaderNames = ContextNames.Concat(new[] {
            "algorithm", "wrapped_key", "nonce", "payload_length"
        }).ToArray();

        private static void Require(bool value) { if (!value) throw new InvalidDataException("CRYPTO_CONTRACT_BLOCKED"); }
        public static void Clear(byte[] bytes) { if (bytes != null) CryptographicOperations.ZeroMemory(bytes); }
        public static string PublicHash(byte[] bytes) { return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(); }

        private static JsonDocument Object(byte[] bytes, string[] names)
        {
            Require(bytes != null && bytes.Length > 0 && bytes.Length <= MaxHeader);
            Require(!(bytes.Length >= 3 && bytes[0] == 239 && bytes[1] == 187 && bytes[2] == 191));
            Utf8.GetString(bytes);
            JsonDocument document = JsonDocument.Parse(bytes, new JsonDocumentOptions {
                AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow, MaxDepth = 3
            });
            try
            {
                Require(document.RootElement.ValueKind == JsonValueKind.Object);
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (JsonProperty property in document.RootElement.EnumerateObject())
                    Require(names.Contains(property.Name, StringComparer.Ordinal) && seen.Add(property.Name));
                Require(seen.Count == names.Length);
                return document;
            }
            catch { document.Dispose(); throw; }
        }

        private static string Text(JsonElement root, string name)
        {
            JsonElement element = root.GetProperty(name);
            Require(element.ValueKind == JsonValueKind.String);
            string value = element.GetString();
            Require(value != null && value.Length <= 1024);
            return value;
        }
        private static long Integer(JsonElement root, string name)
        {
            JsonElement element = root.GetProperty(name);
            Require(element.ValueKind == JsonValueKind.Number && Regex.IsMatch(element.GetRawText(), "^(0|[1-9][0-9]{0,18})\\z", RegexOptions.CultureInvariant));
            Require(element.TryGetInt64(out long value));
            return value;
        }
        private static void Context(JsonElement root)
        {
            Require(Text(root, "schema") == Schema && Text(root, "repository") == "xartaiusx/XI-Server");
            Require(Regex.IsMatch(Text(root, "source_head"), "^[a-f0-9]{40}\\z", RegexOptions.CultureInvariant));
            Require(Text(root, "program_baseline") == ProgramBaseline);
            Require(Regex.IsMatch(Text(root, "workflow_sha256"), "^[a-f0-9]{64}\\z", RegexOptions.CultureInvariant));
            Require(Integer(root, "run_id") > 0 && Integer(root, "run_attempt") == 1);
            Require(Text(root, "request_nonce") == RequestNonce);
            Require(Regex.IsMatch(Text(root, "recipient_sha256"), "^[a-f0-9]{64}\\z", RegexOptions.CultureInvariant));
            Require(root.GetProperty("diagnostic_only").ValueKind == JsonValueKind.True);
            Require(root.GetProperty("acceptance").ValueKind == JsonValueKind.False);
        }
        public static void ValidateContext(byte[] context)
        {
            using (JsonDocument document = Object(context, ContextNames)) Context(document.RootElement);
        }
        public static void ValidatePayloadLength(long length) { Require(length > 0 && length <= MaxPayload); }
        private static void SameContext(JsonElement actual, JsonElement expected)
        {
            foreach (string name in ContextNames)
            {
                JsonElement left = actual.GetProperty(name), right = expected.GetProperty(name);
                Require(left.ValueKind == right.ValueKind);
                if (left.ValueKind == JsonValueKind.String) Require(left.GetString() == right.GetString());
                else Require(left.GetRawText() == right.GetRawText());
            }
        }
        private static byte[] Base64(JsonElement root, string name, int size)
        {
            string text = Text(root, name);
            byte[] bytes = Convert.FromBase64String(text);
            Require(bytes.Length == size && Convert.ToBase64String(bytes) == text);
            return bytes;
        }
        private static RSA Recipient(byte[] spki)
        {
            Require(spki != null && spki.Length > 0 && spki.Length <= MaxHeader);
            RSA rsa = RSA.Create();
            try {
                rsa.ImportSubjectPublicKeyInfo(spki, out int consumed);
                Require(consumed == spki.Length && rsa.KeySize == 4096);
                Require(rsa.ExportSubjectPublicKeyInfo().AsSpan().SequenceEqual(spki));
                return rsa;
            } catch { rsa.Dispose(); throw; }
        }
        private static byte[] Header(JsonElement context, byte[] wrapped, byte[] nonce, int length)
        {
            using (var stream = new MemoryStream())
            {
                using (var writer = new Utf8JsonWriter(stream))
                {
                    writer.WriteStartObject();
                    foreach (string name in ContextNames) { writer.WritePropertyName(name); context.GetProperty(name).WriteTo(writer); }
                    writer.WriteString("algorithm", Algorithm);
                    writer.WriteString("wrapped_key", Convert.ToBase64String(wrapped));
                    writer.WriteString("nonce", Convert.ToBase64String(nonce));
                    writer.WriteNumber("payload_length", length);
                    writer.WriteEndObject();
                }
                byte[] result = stream.ToArray();
                Require(result.Length <= MaxHeader);
                return result;
            }
        }
        public static byte[] Encrypt(byte[] payload, byte[] spki, byte[] context)
        {
            Require(payload != null && AesGcm.IsSupported);
            ValidatePayloadLength(payload.Length);
            using (JsonDocument document = Object(context, ContextNames))
            using (RSA rsa = Recipient(spki))
            {
                Context(document.RootElement);
                Require(Text(document.RootElement, "recipient_sha256") == PublicHash(spki));
                byte[] key = RandomNumberGenerator.GetBytes(32);
                try
                {
                    byte[] nonce = RandomNumberGenerator.GetBytes(12);
                    byte[] wrapped = rsa.Encrypt(key, RSAEncryptionPadding.OaepSHA256);
                    Require(wrapped.Length == 512);
                    byte[] header = Header(document.RootElement, wrapped, nonce, payload.Length);
                    byte[] output = new byte[checked(Magic.Length + 4 + header.Length + payload.Length + 16)];
                    Magic.CopyTo(output, 0);
                    int offset = Magic.Length;
                    output[offset] = (byte)(header.Length >> 24); output[offset + 1] = (byte)(header.Length >> 16);
                    output[offset + 2] = (byte)(header.Length >> 8); output[offset + 3] = (byte)header.Length;
                    header.CopyTo(output, offset + 4);
                    int cipherOffset = offset + 4 + header.Length;
                    using (var aes = new AesGcm(key, 16))
                        aes.Encrypt(nonce, payload, output.AsSpan(cipherOffset, payload.Length), output.AsSpan(cipherOffset + payload.Length, 16), header);
                    return output;
                }
                finally { Clear(key); }
            }
        }
        private static byte[] CheckedHeader(byte[] envelope, byte[] expectedContext)
        {
            Require(envelope != null && envelope.Length >= Magic.Length + 4 + 1 + 16 && envelope.Length <= MaxPayload + MaxHeader + Magic.Length + 20);
            Require(envelope.AsSpan(0, Magic.Length).SequenceEqual(Magic));
            int offset = Magic.Length;
            uint size = ((uint)envelope[offset] << 24) | ((uint)envelope[offset + 1] << 16) | ((uint)envelope[offset + 2] << 8) | envelope[offset + 3];
            Require(size > 0 && size <= MaxHeader && (long)Magic.Length + 4 + size + 16 < envelope.Length);
            byte[] header = envelope.AsSpan(offset + 4, (int)size).ToArray();
            using (JsonDocument actual = Object(header, HeaderNames))
            using (JsonDocument expected = Object(expectedContext, ContextNames))
            {
                Context(actual.RootElement); Context(expected.RootElement);
                SameContext(actual.RootElement, expected.RootElement);
                Require(Text(actual.RootElement, "algorithm") == Algorithm);
                Base64(actual.RootElement, "wrapped_key", 512); Base64(actual.RootElement, "nonce", 12);
                long length = Integer(actual.RootElement, "payload_length");
                Require(length > 0 && length <= MaxPayload && (long)Magic.Length + 4 + header.Length + length + 16 == envelope.Length);
            }
            return header;
        }
        public static void ValidateEnvelope(byte[] envelope, byte[] expectedContext) { CheckedHeader(envelope, expectedContext); }
        public static byte[] Decrypt(byte[] envelope, byte[] privatePkcs8, byte[] expectedContext)
        {
            // All public metadata is matched before a private key is imported or ciphertext decrypted.
            byte[] header = CheckedHeader(envelope, expectedContext);
            Require(privatePkcs8 != null && privatePkcs8.Length > 0 && privatePkcs8.Length <= 16384 && AesGcm.IsSupported);
            using (JsonDocument document = Object(header, HeaderNames))
            using (RSA rsa = RSA.Create())
            {
                rsa.ImportPkcs8PrivateKey(privatePkcs8, out int consumed);
                Require(consumed == privatePkcs8.Length && rsa.KeySize == 4096);
                Require(PublicHash(rsa.ExportSubjectPublicKeyInfo()) == Text(document.RootElement, "recipient_sha256"));
                byte[] key = null;
                byte[] plaintext = null;
                try
                {
                    key = rsa.Decrypt(Base64(document.RootElement, "wrapped_key", 512), RSAEncryptionPadding.OaepSHA256);
                    Require(key.Length == 32);
                    plaintext = new byte[(int)Integer(document.RootElement, "payload_length")];
                    using (var aes = new AesGcm(key, 16))
                        aes.Decrypt(Base64(document.RootElement, "nonce", 12), envelope.AsSpan(Magic.Length + 4 + header.Length, plaintext.Length), envelope.AsSpan(envelope.Length - 16, 16), plaintext, header);
                    return plaintext;
                }
                catch { Clear(plaintext); throw; }
                finally { Clear(key); }
            }
        }

        [DllImport("libc", EntryPoint = "open", SetLastError = true)] private static extern int UnixOpen(string path, int flags);
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle WindowsOpen(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);

        private static string PathWithoutLinks(string path, bool output)
        {
            Require(!String.IsNullOrWhiteSpace(path) && Path.IsPathFullyQualified(path));
            string full = Path.GetFullPath(path);
            string current = output ? Path.GetDirectoryName(full) : full;
            Require(current != null);
            while (current != null)
            {
                FileAttributes attributes = File.GetAttributes(current);
                Require((attributes & FileAttributes.ReparsePoint) == 0);
                if (current != full || output) Require((attributes & FileAttributes.Directory) != 0);
                current = Path.GetDirectoryName(current);
            }
            return full;
        }
        public static void RequireAbsentOutput(string path)
        {
            string full = PathWithoutLinks(path, true);
            try { File.GetAttributes(full); throw new InvalidDataException("CRYPTO_OUTPUT_EXISTS"); }
            catch (FileNotFoundException) { }
        }
        public static byte[] ReadFile(string path, int maximum)
        {
            Require(maximum > 0 && maximum <= MaxPayload + MaxHeader + Magic.Length + 20);
            string full = PathWithoutLinks(path, false);
            SafeFileHandle handle;
            if (OperatingSystem.IsWindows()) handle = WindowsOpen(full, 0x80000000, 1, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
            else if (OperatingSystem.IsLinux()) {
                int descriptor = UnixOpen(full, 0x80000 | 0x20000 | 0x800);
                Require(descriptor >= 0);
                handle = new SafeFileHandle(new IntPtr(descriptor), true);
            } else throw new PlatformNotSupportedException("CRYPTO_PLATFORM_BLOCKED");
            using (handle)
            {
                Require(!handle.IsInvalid);
                FileAttributes attributes = File.GetAttributes(handle);
                Require((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Device)) == 0);
                using (var stream = new FileStream(handle, FileAccess.Read))
                {
                    Require(stream.CanSeek && stream.Length > 0 && stream.Length <= maximum);
                    long length = stream.Length;
                    DateTime modified = File.GetLastWriteTimeUtc(handle);
                    byte[] bytes = new byte[(int)length];
                    stream.ReadExactly(bytes);
                    Require(stream.ReadByte() == -1 && stream.Length == length && File.GetLastWriteTimeUtc(handle) == modified && File.GetAttributes(handle) == attributes);
                    return bytes;
                }
            }
        }
        public static void WriteNew(string path, byte[] bytes)
        {
            Require(bytes != null && bytes.Length > 0 && bytes.Length <= MaxPayload + MaxHeader + Magic.Length + 20);
            RequireAbsentOutput(path);
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, Share = FileShare.None, Options = FileOptions.WriteThrough };
            if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            using (var stream = new FileStream(Path.GetFullPath(path), options)) { stream.Write(bytes); stream.Flush(true); }
        }
    }
}
'@ | Out-Null
}

function Invoke-HostedAsanEncrypt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$PublicSpkiPath,
        [Parameter(Mandatory)][string]$ContextPath,
        [Parameter(Mandatory)][string]$CiphertextPath
    )
    Initialize-HostedAsanCrypto
    [Mochirii.HostedAsanEvidenceV1]::RequireAbsentOutput($CiphertextPath)
    $payload = $null
    try {
        $public = [Mochirii.HostedAsanEvidenceV1]::ReadFile($PublicSpkiPath, 8192)
        $context = [Mochirii.HostedAsanEvidenceV1]::ReadFile($ContextPath, 8192)
        [Mochirii.HostedAsanEvidenceV1]::ValidateContext($context)
        $payload = [Mochirii.HostedAsanEvidenceV1]::ReadFile($ArchivePath, 134217728)
        $ciphertext = [Mochirii.HostedAsanEvidenceV1]::Encrypt($payload, $public, $context)
        [Mochirii.HostedAsanEvidenceV1]::ValidateEnvelope($ciphertext, $context)
        [Mochirii.HostedAsanEvidenceV1]::WriteNew($CiphertextPath, $ciphertext)
    }
    finally { [Mochirii.HostedAsanEvidenceV1]::Clear($payload) }
}

if ($Mode -eq 'Encrypt') {
    try {
        $ErrorActionPreference = 'Stop'
        Invoke-HostedAsanEncrypt -ArchivePath $ArchivePath -PublicSpkiPath $PublicSpkiPath -ContextPath $ContextPath -CiphertextPath $CiphertextPath
        [Console]::Out.WriteLine('HOSTED_ASAN_CIPHERTEXT_WRITTEN')
    }
    catch {
        [Console]::Error.WriteLine('HOSTED_ASAN_CRYPTO_BLOCKED')
        exit 1
    }
}
