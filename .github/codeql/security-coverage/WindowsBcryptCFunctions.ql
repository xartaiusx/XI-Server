/**
 * @name Traced Windows bcrypt C function bodies
 * @description Require real bodies for all four pinned bcrypt C inputs in a traced compilation.
 * @kind metric
 * @id mochirii/telemetry/windows-bcrypt-c-bodies
 * @tags summary
 *       telemetry
 */

import cpp

private predicate requiredBody(string source, string name) {
  source = "bcrypt.c" and name = "bcrypt_hashpw"
  or
  source = "crypt_blowfish.c" and name = "_crypt_blowfish_rn"
  or
  source = "crypt_gensalt.c" and name = "_crypt_gensalt_traditional_rn"
  or
  source = "wrapper.c" and name = "crypt_rn"
}

select count(string source |
  exists(string name, File file, Compilation compilation, Function function |
    requiredBody(source, name) and
    file.getBaseName() = source and
    file.getAbsolutePath().matches(
      "%/bcrypt/7ac6b4178d22a0c3d5fffae21ac54ea887d2b81f/src/" + source
    ) and
    compilation.getAFileCompiled() = file and not compilation.buildModeNone() and
    compilation.normalTermination() and
    function.getName() = name and function.getBlock().getFile() = file
  )
|
  source
)
