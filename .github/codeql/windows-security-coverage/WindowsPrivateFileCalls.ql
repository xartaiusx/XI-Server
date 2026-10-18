/**
 * @name Windows private-file API coverage
 * @description Count distinct required Windows API call families in the exclusive private-file implementation.
 * @kind metric
 * @id mochirii/telemetry/windows-private-file-calls
 * @tags summary
 *       telemetry
 */

import cpp

select count(string api |
  api = [
    "ConvertStringSecurityDescriptorToSecurityDescriptorA", "CreateFileW",
    "GetVolumeInformationByHandleW", "CloseHandle", "LocalFree", "_open_osfhandle", "_fdopen",
    "_close"
  ] and
  exists(FunctionCall call |
    call.getEnclosingFunction().hasQualifiedName("certificateHelpers", "openExclusivePrivateFile") and
    call.getFile().getRelativePath() = "src/common/cert_helpers.h" and
    call.getTarget().getName() = api
  )
|
  api
)
