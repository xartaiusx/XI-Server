/**
 * @name Total native compiler errors including fatal errors
 * @description Count native CompilerError and CompilerCatastrophe diagnostics, explicitly including zero.
 * @kind metric
 * @id mochirii/telemetry/compiler-errors-total
 * @tags summary
 *       telemetry
 */

import cpp

select count(Diagnostic diagnostic |
  diagnostic instanceof CompilerError or diagnostic instanceof CompilerCatastrophe
)
