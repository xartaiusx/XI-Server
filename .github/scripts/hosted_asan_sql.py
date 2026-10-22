"""One hosted, synthetic-only ASAN SQL observation. Import performs no I/O.

Only the owning privacy controller calls these functions. Child output belongs
to its private_command callback; nothing here prints, uploads or dispatches.
This is diagnostic-only and never reclassifies the preserved hosted warning.
"""

from pathlib import Path
import base64
import hashlib
import json
import os
import posixpath
import re
import shlex
import stat
import sys
from types import SimpleNamespace

SOURCE = "75ef2a9b1eb5f74ce1a5b7a5e6bd6c6f557f7483"
NONCE = "4bbc0bb9dc7b4cb7ac767ff2376e3750"
BRANCH = "refs/heads/mochi/hosted-asan-guard-telemetry-20261023"
FILE = "scripts/tests/systems/monstrosity/belligerency.lua"
SUITE = "systems::monstrosity::Monstrosity Belligerency"
CASE = "lets a gladiator attack a monster it claimed"
DATABASE = "mochi_asan_4bbc0bb9dc7b4cb7"
DB_USER = "mochi_diag"
# Public, disposable hosted fixture credential; never a workstation credential.
DB_PASSWORD = "synthetic_only_4bbc0bb9dc7b4cb7"
RECIPE_SHA = "760c435142edb5a8a1c1457465b82989e597a5af2ac754925a84a95cc1f2188d"
HEADER_SHA = "05960e12ee3a3d9cff0bf1080e5355564a600e9eaacec45d82c8b7c57bd6b3e9"
RECIPE_B64 = (
    "IiIiUHVyZSwgcmV2ZXJzaWJsZSBpbnN0cnVtZW50YXRpb24gcmVjaXBlLiBJbXBvcnQgcGVyZm9ybXMgbm8gSS9P"
    "LiIiIgoKaW1wb3J0IGhhc2hsaWIKClNPVVJDRSA9ICI4MDM3ZjAwYzQ0NjYwOGUwMjA0ZDlhMGViYjk3ODljMTgy"
    "NTIyMjg4IgpDQUNIRSA9ICJzcmMvY29tbW9uL2RhdGFiYXNlL2NhY2hpbmdfZGF0YWJhc2UuY3BwIgpNQVJJQSA9"
    "ICJzcmMvY29tbW9uL2RhdGFiYXNlL2xpYm1hcmlhZGIvbGlibWFyaWFkYl9wcmVwYXJlZF9zdGF0ZW1lbnQuY3Bw"
    "IgpIRUFERVIgPSAic3FsX3RpbWluZ19tZWFzdXJlbWVudC5oIgpPUklHSU5BTCA9IHsKICAgIENBQ0hFOiAiMWU5"
    "ZWU2ZWIwOTAxYzZlODJlMmEwODQzM2Q4MjFkNWVkNDk2MTA2YzUwZmY4ODBlODIwNjgwYTk0M2YwMzQ2NCIsCiAg"
    "ICBNQVJJQTogIjBmNzUyMDk2NTBlMzY5YWNmZjI3YWYyM2U3MGI0ZTI3NGE4ODZhNGVkMDFjNGE0MzBkYjUyMWJl"
    "ZDdjZGRjMTAiLAp9CgojIEluY2x1ZGVzIHVzZSB0aGUgc2libGluZyBwcml2YXRlIGhlYWRlcjsgYWxsIHB1Ymxp"
    "YyBpbmNsdWRlIHBhdGhzIHN0YXkgZnJvemVuLgpSRUNJUEVTID0gewogICAgQ0FDSEU6ICgKICAgICAgICAoCiAg"
    "ICAgICAgICAgICIjaW5jbHVkZSA8Y29tbW9uL2RhdGFiYXNlL2NhY2hpbmdfZGF0YWJhc2UuaD5cbiIsCiAgICAg"
    "ICAgICAgICcjaW5jbHVkZSA8Y29tbW9uL2RhdGFiYXNlL2NhY2hpbmdfZGF0YWJhc2UuaD5cblxuI2luY2x1ZGUg"
    "InNxbF90aW1pbmdfbWVhc3VyZW1lbnQuaCJcbicsCiAgICAgICAgKSwKICAgICAgICAoCiAgICAgICAgICAgICIg"
    "ICAgICAgIGNvbnN0IGF1dG8gcXVlcnlUaW1lciA9IG1ha2VRdWVyeVRpbWVyKHJhd1F1ZXJ5KTtcblxuICAgICAg"
    "ICBpZiAocXVlcnlUeXBlID09IFJlc3VsdFNldFR5cGU6OlNlbGVjdCkiLAogICAgICAgICAgICAiICAgICAgICBt"
    "b2NoaV9zcWxfdGltaW5nX2RpYWdub3N0aWM6Ok9ic2VydmF0aW9uIHNxbE9ic2VydmF0aW9uKHJhd1F1ZXJ5KTtc"
    "biIKICAgICAgICAgICAgIiAgICAgICAgY29uc3QgYXV0byBxdWVyeVRpbWVyID0gbWFrZVF1ZXJ5VGltZXIocmF3"
    "UXVlcnkpO1xuIgogICAgICAgICAgICAiICAgICAgICBjb25zdCBtb2NoaV9zcWxfdGltaW5nX2RpYWdub3N0aWM6"
    "OkNsb3NlIHNxbENsb3NlKHNxbE9ic2VydmF0aW9uKTtcblxuIgogICAgICAgICAgICAiICAgICAgICBpZiAocXVl"
    "cnlUeXBlID09IFJlc3VsdFNldFR5cGU6OlNlbGVjdCkiLAogICAgICAgICksCiAgICApLAogICAgTUFSSUE6ICgK"
    "ICAgICAgICAoCiAgICAgICAgICAgICIjaW5jbHVkZSA8Y29tbW9uL2RhdGFiYXNlL2xpYm1hcmlhZGIvbGlibWFy"
    "aWFkYl9wcmVwYXJlZF9zdGF0ZW1lbnQuaD5cbiIsCiAgICAgICAgICAgICcjaW5jbHVkZSA8Y29tbW9uL2RhdGFi"
    "YXNlL2xpYm1hcmlhZGIvbGlibWFyaWFkYl9wcmVwYXJlZF9zdGF0ZW1lbnQuaD5cblxuI2luY2x1ZGUgInNxbF90"
    "aW1pbmdfbWVhc3VyZW1lbnQuaCJcbicsCiAgICAgICAgKSwKICAgICAgICAoCiAgICAgICAgICAgICIgICAgICAg"
    "IGlmIChteXNxbF9zdG10X2V4ZWN1dGUoc3RtdF8pICE9IDApXG4iCiAgICAgICAgICAgICIgICAgICAgIHtcbiIK"
    "ICAgICAgICAgICAgIiAgICAgICAgICAgIHRocm93IGRldGFpbDo6bGlibWFyaWFkYjo6RXJyb3IobXlzcWxfc3Rt"
    "dF9lcnJubyhzdG10XyksIG15c3FsX3N0bXRfZXJyb3Ioc3RtdF8pKTtcbiIKICAgICAgICAgICAgIiAgICAgICAg"
    "fVxuXG4iCiAgICAgICAgICAgICIgICAgICAgIGVuc3VyZVNjaGVtYSgpO1xuIgogICAgICAgICAgICAiICAgICAg"
    "ICBhdXRvIHJvd3MgPSBmZXRjaFJvd3MoKTtcbiIsCiAgICAgICAgICAgICIgICAgICAgIHtcbiIKICAgICAgICAg"
    "ICAgIiAgICAgICAgICAgIGNvbnN0IG1vY2hpX3NxbF90aW1pbmdfZGlhZ25vc3RpYzo6UGhhc2VUaW1lciBwaGFz"
    "ZShtb2NoaV9zcWxfdGltaW5nX2RpYWdub3N0aWM6OlBoYXNlOjpFeGVjdXRlKTtcbiIKICAgICAgICAgICAgIiAg"
    "ICAgICAgICAgIGlmIChteXNxbF9zdG10X2V4ZWN1dGUoc3RtdF8pICE9IDApXG4iCiAgICAgICAgICAgICIgICAg"
    "ICAgICAgICB7XG4iCiAgICAgICAgICAgICIgICAgICAgICAgICAgICAgdGhyb3cgZGV0YWlsOjpsaWJtYXJpYWRi"
    "OjpFcnJvcihteXNxbF9zdG10X2Vycm5vKHN0bXRfKSwgbXlzcWxfc3RtdF9lcnJvcihzdG10XykpO1xuIgogICAg"
    "ICAgICAgICAiICAgICAgICAgICAgfVxuIgogICAgICAgICAgICAiICAgICAgICB9XG5cbiIKICAgICAgICAgICAg"
    "IiAgICAgICAge1xuIgogICAgICAgICAgICAiICAgICAgICAgICAgY29uc3QgbW9jaGlfc3FsX3RpbWluZ19kaWFn"
    "bm9zdGljOjpQaGFzZVRpbWVyIHBoYXNlKG1vY2hpX3NxbF90aW1pbmdfZGlhZ25vc3RpYzo6UGhhc2U6OlNjaGVt"
    "YSk7XG4iCiAgICAgICAgICAgICIgICAgICAgICAgICBlbnN1cmVTY2hlbWEoKTtcbiIKICAgICAgICAgICAgIiAg"
    "ICAgICAgfVxuIgogICAgICAgICAgICAiICAgICAgICBhdXRvIHJvd3MgPSBbJl1cbiIKICAgICAgICAgICAgIiAg"
    "ICAgICAge1xuIgogICAgICAgICAgICAiICAgICAgICAgICAgY29uc3QgbW9jaGlfc3FsX3RpbWluZ19kaWFnbm9z"
    "dGljOjpQaGFzZVRpbWVyIHBoYXNlKG1vY2hpX3NxbF90aW1pbmdfZGlhZ25vc3RpYzo6UGhhc2U6OkZldGNoKTtc"
    "biIKICAgICAgICAgICAgIiAgICAgICAgICAgIHJldHVybiBmZXRjaFJvd3MoKTtcbiIKICAgICAgICAgICAgIiAg"
    "ICAgICAgfSgpO1xuIgogICAgICAgICAgICAiICAgICAgICBtb2NoaV9zcWxfdGltaW5nX2RpYWdub3N0aWM6OnJl"
    "Y29yZFJvd3Mocm93cy5zaXplKCkpO1xuIiwKICAgICAgICApLAogICAgKSwKfQoKCmRlZiByZXF1aXJlKHZhbHVl"
    "KToKICAgIGlmIG5vdCB2YWx1ZToKICAgICAgICByYWlzZSBSdW50aW1lRXJyb3IoIlByaXZhdGUgU1FMIGluc3Ry"
    "dW1lbnRhdGlvbiBzb3VyY2UgY29udHJhY3QgZmFpbGVkLiIpCgoKZGVmIGRpZ2VzdChyYXcpOgogICAgcmV0dXJu"
    "IGhhc2hsaWIuc2hhMjU2KHJhdykuaGV4ZGlnZXN0KCkKCgpkZWYgaW5zdHJ1bWVudChuYW1lLCBvcmlnaW5hbCk6"
    "CiAgICByZXF1aXJlKG5hbWUgaW4gT1JJR0lOQUwgYW5kIGRpZ2VzdChvcmlnaW5hbCkgPT0gT1JJR0lOQUxbbmFt"
    "ZV0pCiAgICB0ZXh0ID0gb3JpZ2luYWwuZGVjb2RlKCJ1dGYtOCIpCiAgICByZXF1aXJlKCJcciIgbm90IGluIHRl"
    "eHQgYW5kICJceDAwIiBub3QgaW4gdGV4dCkKICAgIGZvciBiZWZvcmUsIGFmdGVyIGluIFJFQ0lQRVNbbmFtZV06"
    "CiAgICAgICAgcmVxdWlyZSh0ZXh0LmNvdW50KGJlZm9yZSkgPT0gMSBhbmQgYWZ0ZXIgbm90IGluIHRleHQpCiAg"
    "ICAgICAgdGV4dCA9IHRleHQucmVwbGFjZShiZWZvcmUsIGFmdGVyLCAxKQogICAgcmVzdWx0ID0gdGV4dC5lbmNv"
    "ZGUoInV0Zi04IikKICAgIHJlcXVpcmUocmV2ZXJzZShuYW1lLCByZXN1bHQpID09IG9yaWdpbmFsKQogICAgcmV0"
    "dXJuIHJlc3VsdAoKCmRlZiByZXZlcnNlKG5hbWUsIG1vZGlmaWVkKToKICAgIHJlcXVpcmUobmFtZSBpbiBSRUNJ"
    "UEVTKQogICAgdGV4dCA9IG1vZGlmaWVkLmRlY29kZSgidXRmLTgiKQogICAgZm9yIGJlZm9yZSwgYWZ0ZXIgaW4g"
    "cmV2ZXJzZWQoUkVDSVBFU1tuYW1lXSk6CiAgICAgICAgcmVxdWlyZSh0ZXh0LmNvdW50KGFmdGVyKSA9PSAxKQog"
    "ICAgICAgIHRleHQgPSB0ZXh0LnJlcGxhY2UoYWZ0ZXIsIGJlZm9yZSwgMSkKICAgIHJlc3VsdCA9IHRleHQuZW5j"
    "b2RlKCJ1dGYtOCIpCiAgICByZXF1aXJlKGRpZ2VzdChyZXN1bHQpID09IE9SSUdJTkFMW25hbWVdKQogICAgcmV0"
    "dXJuIHJlc3VsdAo="
)
HEADER_B64 = (
    "I3ByYWdtYSBvbmNlCgovLyBQcml2YXRlIExpbnV4LW9ubHkgZGlhZ25vc3RpYy4gTm8gU1FMIHZhbHVlcyBvciBj"
    "aGFyYWN0ZXIgaWRlbnRpdGllcy4KI2lmICFkZWZpbmVkKF9fbGludXhfXykgfHwgIWRlZmluZWQoX0dOVV9TT1VS"
    "Q0UpCiNlcnJvciBUaGlzIG9ic2VydmF0aW9uIHJlcXVpcmVzIHRoZSBleGlzdGluZyBMaW51eCBHTlUtZmVhdHVy"
    "ZSBlbnZpcm9ubWVudC4KI2VuZGlmCgojaW5jbHVkZSA8YXJyYXk+CiNpbmNsdWRlIDxhdG9taWM+CiNpbmNsdWRl"
    "IDxjZXJybm8+CiNpbmNsdWRlIDxjaHJvbm8+CiNpbmNsdWRlIDxjc3RkZGVmPgojaW5jbHVkZSA8Y3N0ZGlvPgoj"
    "aW5jbHVkZSA8c3RyaW5nX3ZpZXc+CiNpbmNsdWRlIDxzeXMvcmVzb3VyY2UuaD4KI2luY2x1ZGUgPHVuaXN0ZC5o"
    "PgoKbmFtZXNwYWNlIG1vY2hpX3NxbF90aW1pbmdfZGlhZ25vc3RpYwp7CnVzaW5nIENsb2NrID0gc3RkOjpjaHJv"
    "bm86OnN0ZWFkeV9jbG9jazsKdXNpbmcgTmFub3NlY29uZHMgPSBzdGQ6OmNocm9ubzo6bmFub3NlY29uZHM7Cgpp"
    "bmxpbmUgY29uc3RleHByIHN0ZDo6c3RyaW5nX3ZpZXcgVGFyZ2V0ID0KICAgICJTRUxFQ1QgY2hhcmlkLCBqb2Jp"
    "ZCwgY2FwYWNpdHlfcG9pbnRzLCBqb2JfcG9pbnRzLCAiCiAgICAiam9iX3BvaW50c19zcGVudCwganB0eXBlMCwg"
    "anB0eXBlMSwganB0eXBlMiwgIgogICAgImpwdHlwZTMsIGpwdHlwZTQsIGpwdHlwZTUsIGpwdHlwZTYsICIKICAg"
    "ICJqcHR5cGU3LCBqcHR5cGU4LCBqcHR5cGU5ICIKICAgICJGUk9NIGNoYXJfam9iX3BvaW50cyAiCiAgICAiV0hF"
    "UkUgY2hhcmlkID0gPyAiCiAgICAiT1JERVIgQlkgam9iaWQgQVNDIjsKCmVudW0gY2xhc3MgUGhhc2UgOiB1bnNp"
    "Z25lZCBpbnQKewogICAgRXhlY3V0ZSA9IDAsCiAgICBTY2hlbWEgPSAxLAogICAgRmV0Y2ggPSAyLAp9OwoKY2xh"
    "c3MgT2JzZXJ2YXRpb247CmlubGluZSBzdGQ6OmF0b21pY19mbGFnIENsYWltZWQgPSBBVE9NSUNfRkxBR19JTklU"
    "OwppbmxpbmUgdGhyZWFkX2xvY2FsIE9ic2VydmF0aW9uKiBBY3RpdmUgPSBudWxscHRyOwoKY2xhc3MgT2JzZXJ2"
    "YXRpb24gZmluYWwKewpwdWJsaWM6CiAgICBleHBsaWNpdCBPYnNlcnZhdGlvbihzdGQ6OnN0cmluZ192aWV3IHF1"
    "ZXJ5KSBub2V4Y2VwdAogICAgewogICAgICAgIGNvbnN0IGludCBzYXZlZEVycm5vID0gZXJybm87CiAgICAgICAg"
    "ZW5hYmxlZF8gPSBxdWVyeSA9PSBUYXJnZXQgJiYgIUNsYWltZWQudGVzdF9hbmRfc2V0KHN0ZDo6bWVtb3J5X29y"
    "ZGVyX3JlbGF4ZWQpOwogICAgICAgIGlmIChlbmFibGVkXykKICAgICAgICB7CiAgICAgICAgICAgIHRocmVhZF8g"
    "PSBzdGF0aWNfY2FzdDxsb25nIGxvbmc+KDo6Z2V0dGlkKCkpOwogICAgICAgICAgICBiZWZvcmVWYWxpZF8gPSA6"
    "OmdldHJ1c2FnZShSVVNBR0VfVEhSRUFELCAmYmVmb3JlXykgPT0gMDsKICAgICAgICAgICAgc3RhcnRfID0gQ2xv"
    "Y2s6Om5vdygpOwogICAgICAgICAgICBBY3RpdmUgPSB0aGlzOwogICAgICAgIH0KICAgICAgICBlcnJubyA9IHNh"
    "dmVkRXJybm87CiAgICB9CgogICAgT2JzZXJ2YXRpb24oY29uc3QgT2JzZXJ2YXRpb24mKSA9IGRlbGV0ZTsKICAg"
    "IE9ic2VydmF0aW9uJiBvcGVyYXRvcj0oY29uc3QgT2JzZXJ2YXRpb24mKSA9IGRlbGV0ZTsKCiAgICB+T2JzZXJ2"
    "YXRpb24oKSBub2V4Y2VwdAogICAgewogICAgICAgIGlmICghZW5hYmxlZF8pCiAgICAgICAgewogICAgICAgICAg"
    "ICByZXR1cm47CiAgICAgICAgfQogICAgICAgIGNvbnN0IGludCBzYXZlZEVycm5vID0gZXJybm87CiAgICAgICAg"
    "QWN0aXZlID0gbnVsbHB0cjsKICAgICAgICAvLyBUaGlzIGRlc3RydWN0b3IgcnVucyBhZnRlciB0aGUgb3JpZ2lu"
    "YWwgcXVlcnlUaW1lciBkZXN0cnVjdG9yLgogICAgICAgIGNvbnN0IGJvb2wgdmFsaWQgPSBiZWZvcmVWYWxpZF8g"
    "JiYgYWZ0ZXJWYWxpZF87CiAgICAgICAgY29uc3QgYXV0byB1c2VyID0gdmFsaWQgPyBjcHVEZWx0YShiZWZvcmVf"
    "LnJ1X3V0aW1lLCBhZnRlcl8ucnVfdXRpbWUpIDogLTFMTDsKICAgICAgICBjb25zdCBhdXRvIHN5c3RlbSA9IHZh"
    "bGlkID8gY3B1RGVsdGEoYmVmb3JlXy5ydV9zdGltZSwgYWZ0ZXJfLnJ1X3N0aW1lKSA6IC0xTEw7CiAgICAgICAg"
    "Y29uc3QgYXV0byB2b2x1bnRhcnkgPSB2YWxpZCA/IHN0YXRpY19jYXN0PGxvbmcgbG9uZz4oYWZ0ZXJfLnJ1X252"
    "Y3N3IC0gYmVmb3JlXy5ydV9udmNzdykgOiAtMUxMOwogICAgICAgIGNvbnN0IGF1dG8gaW52b2x1bnRhcnkgPSB2"
    "YWxpZCA/IHN0YXRpY19jYXN0PGxvbmcgbG9uZz4oYWZ0ZXJfLnJ1X25pdmNzdyAtIGJlZm9yZV8ucnVfbml2Y3N3"
    "KSA6IC0xTEw7CiAgICAgICAgc3RkOjphcnJheTxjaGFyLCAxMDI0PiBvdXRwdXR7fTsKICAgICAgICBjb25zdCBp"
    "bnQgY291bnQgPSBzdGQ6OnNucHJpbnRmKAogICAgICAgICAgICBvdXRwdXQuZGF0YSgpLCBvdXRwdXQuc2l6ZSgp"
    "LAogICAgICAgICAgICAiTU9DSElfU1FMX1RJTUlOR19WMSB7XCJkaWFnbm9zdGljX29ubHlcIjp0cnVlLFwiYWNj"
    "ZXB0YW5jZVwiOmZhbHNlLCIKICAgICAgICAgICAgIlwicXVlcnlfdGFnXCI6XCJsb2FkX2pvYl9wb2ludHNfZmly"
    "c3RcIixcInRocmVhZF9pZFwiOiVsbGQsIgogICAgICAgICAgICAiXCJjbG9zZWRcIjolZCxcInJlc291cmNlX3Zh"
    "bGlkXCI6JWQsXCJwaGFzZV9tYXNrXCI6JXUsIgogICAgICAgICAgICAiXCJyYXdfcXVlcnlfYnJhY2tldF9uc1wi"
    "OiVsbGQsXCJleGVjdXRlX25zXCI6JWxsZCwiCiAgICAgICAgICAgICJcInNjaGVtYV9uc1wiOiVsbGQsXCJmZXRj"
    "aF9uc1wiOiVsbGQsXCJyb3dzXCI6JXp1LFwicm93c19yZWNvcmRlZFwiOiVkLCIKICAgICAgICAgICAgIlwidXNl"
    "cl9jcHVfbnNcIjolbGxkLFwic3lzdGVtX2NwdV9uc1wiOiVsbGQsIgogICAgICAgICAgICAiXCJ2b2x1bnRhcnlf"
    "c3dpdGNoZXNcIjolbGxkLFwiaW52b2x1bnRhcnlfc3dpdGNoZXNcIjolbGxkLCIKICAgICAgICAgICAgIlwicGhh"
    "c2VfY2xvY2tfc2FtcGxlc1wiOiV1LFwicmVzb3VyY2Vfc2FtcGxlc1wiOjJ9XG4iLAogICAgICAgICAgICB0aHJl"
    "YWRfLCBjbG9zZWRfID8gMSA6IDAsIHZhbGlkID8gMSA6IDAsCiAgICAgICAgICAgIHBoYXNlTWFza18sIHJhd18s"
    "IHBoYXNlc19bMF0sIHBoYXNlc19bMV0sIHBoYXNlc19bMl0sCiAgICAgICAgICAgIHJvd3NfLCByb3dzUmVjb3Jk"
    "ZWRfID8gMSA6IDAsIHVzZXIsIHN5c3RlbSwKICAgICAgICAgICAgdm9sdW50YXJ5LCBpbnZvbHVudGFyeSwgcGhh"
    "c2VTYW1wbGVzXyk7CiAgICAgICAgaWYgKGNvdW50ID4gMCAmJiBzdGF0aWNfY2FzdDxzdGQ6OnNpemVfdD4oY291"
    "bnQpIDwgb3V0cHV0LnNpemUoKSkKICAgICAgICB7CiAgICAgICAgICAgIC8vIE9uZSBib3VuZGVkIHdyaXRlIG9u"
    "bHkuIFRoZSBjb250cm9sbGVyIHJlamVjdHMgbWlzc2luZy9wYXJ0aWFsIG91dHB1dC4KICAgICAgICAgICAgY29u"
    "c3QgYXV0byB3cml0dGVuID0gOjp3cml0ZShTVERFUlJfRklMRU5PLCBvdXRwdXQuZGF0YSgpLCBzdGF0aWNfY2Fz"
    "dDxzdGQ6OnNpemVfdD4oY291bnQpKTsKICAgICAgICAgICAgKHZvaWQpd3JpdHRlbjsKICAgICAgICB9CiAgICAg"
    "ICAgZXJybm8gPSBzYXZlZEVycm5vOwogICAgfQoKICAgIHZvaWQgY2xvc2UoKSBub2V4Y2VwdAogICAgewogICAg"
    "ICAgIGlmICghZW5hYmxlZF8pCiAgICAgICAgewogICAgICAgICAgICByZXR1cm47CiAgICAgICAgfQogICAgICAg"
    "IGNvbnN0IGludCBzYXZlZEVycm5vID0gZXJybm87CiAgICAgICAgcmF3XyA9IHN0ZDo6Y2hyb25vOjpkdXJhdGlv"
    "bl9jYXN0PE5hbm9zZWNvbmRzPihDbG9jazo6bm93KCkgLSBzdGFydF8pLmNvdW50KCk7CiAgICAgICAgYWZ0ZXJW"
    "YWxpZF8gPSA6OmdldHJ1c2FnZShSVVNBR0VfVEhSRUFELCAmYWZ0ZXJfKSA9PSAwOwogICAgICAgIGNsb3NlZF8g"
    "PSB0cnVlOwogICAgICAgIGVycm5vID0gc2F2ZWRFcnJubzsKICAgIH0KCiAgICB2b2lkIHBoYXNlKFBoYXNlIGtp"
    "bmQsIGxvbmcgbG9uZyBlbGFwc2VkKSBub2V4Y2VwdAogICAgewogICAgICAgIGNvbnN0IGF1dG8gaW5kZXggPSBz"
    "dGF0aWNfY2FzdDx1bnNpZ25lZCBpbnQ+KGtpbmQpOwogICAgICAgIHBoYXNlc19baW5kZXhdICs9IGVsYXBzZWQ7"
    "CiAgICAgICAgcGhhc2VNYXNrXyB8PSAxVSA8PCBpbmRleDsKICAgICAgICBwaGFzZVNhbXBsZXNfICs9IDI7CiAg"
    "ICB9CgogICAgdm9pZCByb3dzKHN0ZDo6c2l6ZV90IGNvdW50KSBub2V4Y2VwdAogICAgewogICAgICAgIHJvd3Nf"
    "ID0gY291bnQ7CiAgICAgICAgcm93c1JlY29yZGVkXyA9IHRydWU7CiAgICB9Cgpwcml2YXRlOgogICAgc3RhdGlj"
    "IGxvbmcgbG9uZyBjcHVEZWx0YShjb25zdCB0aW1ldmFsJiBiZWZvcmUsIGNvbnN0IHRpbWV2YWwmIGFmdGVyKSBu"
    "b2V4Y2VwdAogICAgewogICAgICAgIHJldHVybiAoc3RhdGljX2Nhc3Q8bG9uZyBsb25nPihhZnRlci50dl9zZWMp"
    "IC0gc3RhdGljX2Nhc3Q8bG9uZyBsb25nPihiZWZvcmUudHZfc2VjKSkgKiAxMDAwMDAwMDAwTEwgKwogICAgICAg"
    "ICAgICAgICAoc3RhdGljX2Nhc3Q8bG9uZyBsb25nPihhZnRlci50dl91c2VjKSAtIHN0YXRpY19jYXN0PGxvbmcg"
    "bG9uZz4oYmVmb3JlLnR2X3VzZWMpKSAqIDEwMDBMTDsKICAgIH0KCiAgICBib29sIGVuYWJsZWRfID0gZmFsc2U7"
    "CiAgICBib29sIGJlZm9yZVZhbGlkXyA9IGZhbHNlOwogICAgYm9vbCBhZnRlclZhbGlkXyA9IGZhbHNlOwogICAg"
    "Ym9vbCBjbG9zZWRfID0gZmFsc2U7CiAgICBib29sIHJvd3NSZWNvcmRlZF8gPSBmYWxzZTsKICAgIGxvbmcgbG9u"
    "ZyB0aHJlYWRfID0gMDsKICAgIENsb2NrOjp0aW1lX3BvaW50IHN0YXJ0X3t9OwogICAgcnVzYWdlIGJlZm9yZV97"
    "fTsKICAgIHJ1c2FnZSBhZnRlcl97fTsKICAgIGxvbmcgbG9uZyByYXdfID0gMDsKICAgIHN0ZDo6YXJyYXk8bG9u"
    "ZyBsb25nLCAzPiBwaGFzZXNfe307CiAgICB1bnNpZ25lZCBpbnQgcGhhc2VNYXNrXyA9IDA7CiAgICB1bnNpZ25l"
    "ZCBpbnQgcGhhc2VTYW1wbGVzXyA9IDA7CiAgICBzdGQ6OnNpemVfdCByb3dzXyA9IDA7Cn07CgpjbGFzcyBDbG9z"
    "ZSBmaW5hbAp7CnB1YmxpYzoKICAgIGV4cGxpY2l0IENsb3NlKE9ic2VydmF0aW9uJiBvYnNlcnZhdGlvbikgbm9l"
    "eGNlcHQgOiBvYnNlcnZhdGlvbl8ob2JzZXJ2YXRpb24pIHt9CiAgICBDbG9zZShjb25zdCBDbG9zZSYpID0gZGVs"
    "ZXRlOwogICAgQ2xvc2UmIG9wZXJhdG9yPShjb25zdCBDbG9zZSYpID0gZGVsZXRlOwogICAgfkNsb3NlKCkgbm9l"
    "eGNlcHQgeyBvYnNlcnZhdGlvbl8uY2xvc2UoKTsgfQoKcHJpdmF0ZToKICAgIE9ic2VydmF0aW9uJiBvYnNlcnZh"
    "dGlvbl87Cn07CgpjbGFzcyBQaGFzZVRpbWVyIGZpbmFsCnsKcHVibGljOgogICAgZXhwbGljaXQgUGhhc2VUaW1l"
    "cihQaGFzZSBraW5kKSBub2V4Y2VwdCA6IG93bmVyXyhBY3RpdmUpLCBraW5kXyhraW5kKQogICAgewogICAgICAg"
    "IGlmIChvd25lcl8pCiAgICAgICAgewogICAgICAgICAgICBjb25zdCBpbnQgc2F2ZWRFcnJubyA9IGVycm5vOwog"
    "ICAgICAgICAgICBzdGFydF8gPSBDbG9jazo6bm93KCk7CiAgICAgICAgICAgIGVycm5vID0gc2F2ZWRFcnJubzsK"
    "ICAgICAgICB9CiAgICB9CiAgICBQaGFzZVRpbWVyKGNvbnN0IFBoYXNlVGltZXImKSA9IGRlbGV0ZTsKICAgIFBo"
    "YXNlVGltZXImIG9wZXJhdG9yPShjb25zdCBQaGFzZVRpbWVyJikgPSBkZWxldGU7CiAgICB+UGhhc2VUaW1lcigp"
    "IG5vZXhjZXB0CiAgICB7CiAgICAgICAgaWYgKG93bmVyXykKICAgICAgICB7CiAgICAgICAgICAgIGNvbnN0IGlu"
    "dCBzYXZlZEVycm5vID0gZXJybm87CiAgICAgICAgICAgIGNvbnN0IGF1dG8gZWxhcHNlZCA9IHN0ZDo6Y2hyb25v"
    "OjpkdXJhdGlvbl9jYXN0PE5hbm9zZWNvbmRzPihDbG9jazo6bm93KCkgLSBzdGFydF8pLmNvdW50KCk7CiAgICAg"
    "ICAgICAgIG93bmVyXy0+cGhhc2Uoa2luZF8sIGVsYXBzZWQpOwogICAgICAgICAgICBlcnJubyA9IHNhdmVkRXJy"
    "bm87CiAgICAgICAgfQogICAgfQoKcHJpdmF0ZToKICAgIE9ic2VydmF0aW9uKiBvd25lcl87CiAgICBQaGFzZSBr"
    "aW5kXzsKICAgIENsb2NrOjp0aW1lX3BvaW50IHN0YXJ0X3t9Owp9OwoKaW5saW5lIHZvaWQgcmVjb3JkUm93cyhz"
    "dGQ6OnNpemVfdCBjb3VudCkgbm9leGNlcHQKewogICAgaWYgKEFjdGl2ZSkKICAgIHsKICAgICAgICBBY3RpdmUt"
    "PnJvd3MoY291bnQpOwogICAgfQp9Cn0gLy8gbmFtZXNwYWNlIG1vY2hpX3NxbF90aW1pbmdfZGlhZ25vc3RpYwo="
)
SQL_FILES = (
    "src/common/database/caching_database.cpp",
    "src/common/database/libmariadb/libmariadb_prepared_statement.cpp",
)
CASE_NAMES = (
    "lets a gladiator attack a flagged Monipulator",
    "refuses a gladiator attacking an unflagged Monipulator",
    "lets a flagged Monipulator attack a gladiator",
    "refuses an unflagged Monipulator attacking a gladiator",
    "lets a flagged Monipulator attack a monster",
    "lets a gladiator attack a monster beside a flagged Monipulator",
    "lets a unflagged Monipulator attack a monster",
    "lets a gladiator attack a monster beside a unflagged Monipulator",
    "keeps a Monipulator off a monster a gladiator claimed",
    "keeps a gladiator off a monster a Monipulator claimed",
    "lets a Monipulator attack a monster it claimed",
    CASE,
    "keeps a Monipulator under Gestation out of reach",
    "stops Relinquish when a gladiator attacks",
    "takes only a tenth of the infamy when the gladiator holds no prestige",
    "moves up to a fifth of the infamy to the gladiator",
    "moves prestige to the Monipulator that defeats a gladiator",
    "answers a /check on a Monipulator like one on a monster",
    "refuses a trade to a Monipulator",
    "refuses a trade from a Monipulator",
)
DEPENDENCIES = {
    "p-ranav/argparse",
    "chriskohlhoff/asio",
    "zach2good/libbcrypt",
    "catchorg/catch2",
    "yhirose/cpp-httplib",
    "jeremy-rifkin/cpptrace",
    "mapbox/earcut.hpp",
    "spartanj/efsw",
    "martinmoene/expected-lite",
    "thisistherk/fast_obj",
    "fmtlib/fmt",
    "naios/function2",
    "stephenberry/glaze",
    "nlohmann/json",
    "neargye/magic_enum",
    "imneme/pcg-cpp",
    "recastnavigation/recastnavigation",
    "gabime/spdlog",
    "ikalnytskyi/termcolor",
    "martinus/unordered_dense",
    "nemtrif/utfcpp",
    "madler/zlib",
}
PACKAGE_IDENTITIES = {
    "argparse": "p-ranav/argparse",
    "asio": "chriskohlhoff/asio",
    "bcrypt": "zach2good/libbcrypt",
    "catch2": "catchorg/catch2",
    "cpp-httplib": "yhirose/cpp-httplib",
    "cpptrace": "jeremy-rifkin/cpptrace",
    "earcut_hpp": "mapbox/earcut.hpp",
    "efsw": "spartanj/efsw",
    "expected-lite": "martinmoene/expected-lite",
    "fast_obj": "thisistherk/fast_obj",
    "fmt": "fmtlib/fmt",
    "function2": "naios/function2",
    "glaze": "stephenberry/glaze",
    "json": "nlohmann/json",
    "magic_enum": "neargye/magic_enum",
    "pcg-cpp": "imneme/pcg-cpp",
    "recastnavigation": "recastnavigation/recastnavigation",
    "spdlog": "gabime/spdlog",
    "termcolor": "ikalnytskyi/termcolor",
    "unordered_dense": "martinus/unordered_dense",
    "utfcpp": "nemtrif/utfcpp",
    "zlib": "madler/zlib",
}
# Exact75ef ext/CMakeLists.txt package contracts, corroborated by immutable
# official GitHub trees/blobs in the independently reviewed private receipt.
PUBLIC_CONTRACTS_SHA = (
    "2117563b99c34a4c183e6a7b1cf1cea16192ea68af293fb43a55d762f405d854"
)
NESTED_CONTRACTS = {
    "mapbox/earcut.hpp": {
        "parent": "4811a2b69b91f6127a75e780de6e2113609ddabb",
        "blob": "728bde6c012499d4146d699294c945766a8d98b3",
        "path": "glfw",
        "child": "90e22947c60b0c1fa47cf1496790ce1942e4a5d8",
        "identity": "glfw/glfw",
        "origin": "https://github.com/glfw/glfw.git",
        "modules": "W3N1Ym1vZHVsZSAiZ2xmdyJdCglwYXRoID0gZ2xmdwoJdXJsID0gaHR0cHM6Ly9naXRodWIuY29tL2dsZncvZ2xmdy5naXQK",
    },
    "naios/function2": {
        "parent": "a354bd093d2b6e50c9325dbce84d20b4e77aabc6",
        "blob": "6889aed06052875cd3df8f39c24c4065a3e7237f",
        "path": "test/googletest",
        "child": "7d955430d1f5fa3652000e407f2a46a9bfccbca3",
        "identity": "google/googletest",
        "origin": "https://github.com/google/googletest.git",
        "modules": "W3N1Ym1vZHVsZSAidGVzdC9nb29nbGV0ZXN0Il0KCXBhdGggPSB0ZXN0L2dvb2dsZXRlc3QKCXVybCA9IGh0dHBzOi8vZ2l0aHViLmNvbS9nb29nbGUvZ29vZ2xldGVzdC5naXQK",
    },
}
EFSW_COMMIT = "22f17a0bcdf3a4edf61f8b14328391463389e548"
ZLIB_CONFIGURED = {
    "commit": "51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf",
    "cmake_sha256": "ab5f3afca6fe38983dc30a28da4877706e3a690a564eda3d4929fff39dab190e",
    "zconf_sha256": "f5134250a67d57459234b63858f0d9d3ef8dcc48e9e1028d3f4fdcf6eae677ae",
}
PRIVATE_TABLES = (
    "accounts",
    "chars",
    "char_inventory",
    "char_vars",
    "char_job_points",
    "char_monstrosity",
)
BASE_ENV_KEYS = {
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
    "CI",
    "PYTHONDONTWRITEBYTECODE",
    "PYTHONNOUSERSITE",
}
INVENTORY_NAMES = {
    "argparse",
    "asio",
    "bcrypt",
    "catch2",
    "cpp-httplib",
    "cpptrace",
    "earcut_hpp",
    "efsw",
    "expected-lite",
    "fast_obj",
    "fmt",
    "function2",
    "glaze",
    "json",
    "magic_enum",
    "pcg-cpp",
    "recastnavigation",
    "spdlog",
    "termcolor",
    "unordered_dense",
    "utfcpp",
    "zlib",
    "cpm",
    ".git",
    "CPM_0.40.2.cmake",
}
INVENTORY_LIMITS = {"depth": 2, "directories": 256, "entries": 4096, "path_bytes": 1024}


def require(value):
    if not value:
        raise RuntimeError("Hosted ASAN diagnostic contract blocked.")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def directory_fd(path, private=False):
    require(isinstance(path, Path) and path.is_absolute() and ".." not in path.parts)
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open("/", flags)
    try:
        for part in path.parts[1:]:
            next_fd = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        info = os.fstat(fd)
        require(info.st_uid in {0, os.geteuid()})
        require(
            (info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o700)
            if private
            else not info.st_mode & 0o022
        )
        return fd
    except BaseException:
        os.close(fd)
        raise


def leaf_fd(path, flags, *, private=False, mode=0o600):
    parent = directory_fd(path.parent, private=private)
    try:
        return os.open(
            path.name,
            flags | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            mode,
            dir_fd=parent,
        )
    finally:
        os.close(parent)


def checked_directory(path, private=False):
    fd = directory_fd(path, private=private)
    try:
        require(os.fstat(fd).st_uid == os.geteuid())
    finally:
        os.close(fd)
    return path


def read_file(path, *, private=False, limit=16 * 1024 * 1024):
    fd = leaf_fd(path, os.O_RDONLY, private=private)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1)
        require(before.st_uid in {0, os.geteuid()} and 0 < before.st_size <= limit)
        require(not private or stat.S_IMODE(before.st_mode) == 0o600)
        raw = bytearray()
        while part := os.read(fd, min(1024 * 1024, before.st_size + 1 - len(raw))):
            raw.extend(part)
            require(len(raw) <= before.st_size)
        after = os.fstat(fd)
        require(
            len(raw) == before.st_size
            and all(
                getattr(before, key) == getattr(after, key)
                for key in (
                    "st_dev",
                    "st_ino",
                    "st_mode",
                    "st_uid",
                    "st_nlink",
                    "st_size",
                    "st_mtime_ns",
                    "st_ctime_ns",
                )
            )
        )
        return bytes(raw)
    finally:
        os.close(fd)


def file_sha(path):
    # Binary/tool hashing is streamed; no executable is loaded by Python.
    fd = leaf_fd(path, os.O_RDONLY)
    try:
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode) and 0 <= before.st_size <= 2**31)
        digest = hashlib.sha256()
        total = 0
        while part := os.read(fd, 1024 * 1024):
            total += len(part)
            require(total <= before.st_size)
            digest.update(part)
        after = os.fstat(fd)
        require(
            total == before.st_size
            and all(
                getattr(before, key) == getattr(after, key)
                for key in ("st_dev", "st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")
            )
        )
        return digest.hexdigest()
    finally:
        os.close(fd)


def prefix(path, size):
    fd = leaf_fd(path, os.O_RDONLY)
    try:
        info = os.fstat(fd)
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_uid == os.geteuid()
            and info.st_size >= size
        )
        return os.read(fd, size)
    finally:
        os.close(fd)


def write_new(path, raw):
    require(isinstance(raw, bytes) and 0 < len(raw) <= 32 * 1024 * 1024)
    fd = leaf_fd(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, private=True)
    try:
        offset = 0
        while offset < len(raw):
            count = os.write(fd, raw[offset:])
            require(count > 0)
            offset += count
        os.fsync(fd)
    finally:
        os.close(fd)


def write_json(path, value):
    write_new(path, (json.dumps(value, sort_keys=True, indent=2) + "\n").encode())


def normalize_context(ctx):
    require(type(ctx) in {dict, SimpleNamespace})
    result = vars(ctx).copy() if type(ctx) is SimpleNamespace else ctx.copy()
    require(
        set(result)
        == {
            "work",
            "evidence",
            "program",
            "controller",
            "env",
            "nonce",
            "request_nonce",
            "source",
            "expected_cpp",
            "expected_executed",
            "expected_filtered",
        }
    )
    return result


def validate_context(ctx):
    require(type(ctx) is dict)
    require(ctx["nonce"] == ctx["request_nonce"] == NONCE and ctx["source"] == SOURCE)
    require(
        ctx["expected_cpp"] == 103
        and ctx["expected_executed"] == 1
        and ctx["expected_filtered"] == 19
    )
    require(
        all(
            type(ctx[name]) is int
            for name in ("expected_cpp", "expected_executed", "expected_filtered")
        )
    )
    require(
        os.environ.get("GITHUB_ACTIONS") == "true"
        and os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted"
        and os.environ.get("RUNNER_OS") == "Linux"
        and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
        and os.environ.get("GITHUB_REPOSITORY") == "xartaiusx/XI-Server"
        and os.environ.get("GITHUB_ACTOR") == "xartaiusx"
        and os.environ.get("GITHUB_TRIGGERING_ACTOR") == "xartaiusx"
        and os.environ.get("GITHUB_RUN_ATTEMPT") == "1"
        and os.environ.get("GITHUB_REF") == BRANCH
    )
    require(re.fullmatch(r"[1-9][0-9]{0,19}", os.environ.get("GITHUB_RUN_ID", "")))
    temp = Path(os.environ["RUNNER_TEMP"])
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    require(
        ctx["work"] == temp / ("mochirii-asan-" + NONCE)
        and ctx["evidence"] == ctx["work"] / "evidence"
        and ctx["program"] == workspace / "program"
        and ctx["controller"] == workspace / "diagnostic"
    )
    checked_directory(ctx["work"], private=True)
    checked_directory(ctx["evidence"], private=True)
    checked_directory(ctx["program"])
    checked_directory(ctx["controller"])
    require(isinstance(ctx["env"], dict) and set(ctx["env"]) <= BASE_ENV_KEYS)
    require(
        all(
            isinstance(key, str) and isinstance(value, str) and "\x00" not in value
            for key, value in ctx["env"].items()
        )
    )
    os.umask(0o077)


def child_env(ctx, extra=None):
    env = dict(ctx["env"])
    env.update(
        {
            "HOME": str(ctx["work"] / "home"),
            "TMPDIR": str(ctx["work"] / "tmp"),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
    )
    if extra:
        env.update(extra)
    return env


def run(
    ctx,
    private_command,
    label,
    argv,
    *,
    cwd=None,
    timeout=300,
    env=None,
    check=True,
    capture=False,
):
    require(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", label))
    require(
        isinstance(argv, list)
        and argv
        and all(isinstance(x, str) and "\x00" not in x for x in argv)
    )
    result = private_command(
        label,
        argv,
        cwd=cwd or ctx["program"],
        timeout=timeout,
        env=env or child_env(ctx),
        check=check,
        capture=capture,
    )
    require(isinstance(result, dict) and type(result["returncode"]) is int)
    require(isinstance(result["log"], Path) and result["log"].parent == ctx["evidence"])
    info = result["log"].lstat()
    require(
        stat.S_ISREG(info.st_mode)
        and info.st_uid == os.geteuid()
        and info.st_nlink == 1
        and stat.S_IMODE(info.st_mode) == 0o600
    )
    require(
        isinstance(result["stdout"], bytes) and len(result["stdout"]) <= 1024 * 1024
    )
    require(capture or result["stdout"] == b"")
    require(not check or result["returncode"] == 0)
    ctx.setdefault("_logs", set()).add(result["log"].name)
    return result


def git_output(ctx, private_command, label, directory, *args):
    return run(
        ctx,
        private_command,
        label,
        ["/usr/bin/git", "--no-optional-locks", "-C", str(directory), *args],
        capture=True,
    )["stdout"]


def source_proof(ctx, private_command, label, modified):
    program = ctx["program"]
    require(
        git_output(
            ctx, private_command, label + "-head", program, "rev-parse", "HEAD"
        ).strip()
        == SOURCE.encode()
    )
    require(
        not git_output(
            ctx,
            private_command,
            label + "-index",
            program,
            "diff",
            "--cached",
            "--name-only",
            SOURCE,
        )
    )
    actual = (
        git_output(
            ctx,
            private_command,
            label + "-diff",
            program,
            "diff",
            "--no-ext-diff",
            "--no-textconv",
            "--name-only",
            SOURCE,
        )
        .decode()
        .splitlines()
    )
    require(sorted(actual) == sorted(SQL_FILES) if modified else actual == [])
    proof = {name: sha(read_file(program / name)) for name in SQL_FILES}
    recipe, header = instrumentation()
    for name in SQL_FILES:
        raw = read_file(program / name)
        if modified:
            recipe["reverse"](name, raw)
            require(
                read_file((program / name).parent / "sql_timing_measurement.h")
                == header
            )
        else:
            require(sha(raw) == recipe["ORIGINAL"][name])
    return proof


def instrumentation():
    recipe = base64.b64decode(RECIPE_B64, validate=True)
    header = base64.b64decode(HEADER_B64, validate=True)
    require(sha(recipe) == RECIPE_SHA and sha(header) == HEADER_SHA)
    scope = {}
    exec(compile(recipe, "reviewed_sql_timing_recipe", "exec"), scope)
    return scope, header


def instrument_program(ctx):
    recipe, header = instrumentation()
    changes = {}
    for name in SQL_FILES:
        path = ctx["program"] / name
        before = read_file(path)
        after = recipe["instrument"](name, before)
        fd = leaf_fd(path, os.O_RDWR)
        try:
            require(os.fstat(fd).st_uid == os.geteuid() and os.fstat(fd).st_nlink == 1)
            require(os.read(fd, len(before) + 1) == before)
            os.ftruncate(fd, 0)
            os.lseek(fd, 0, os.SEEK_SET)
            offset = 0
            while offset < len(after):
                count = os.write(fd, after[offset:])
                require(count > 0)
                offset += count
            os.fsync(fd)
        finally:
            os.close(fd)
        target = path.parent / "sql_timing_measurement.h"
        require(not os.path.lexists(target))
        fd = leaf_fd(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
        try:
            require(os.write(fd, header) == len(header))
            os.fsync(fd)
        finally:
            os.close(fd)
        changes[name] = {"before_sha256": sha(before), "after_sha256": sha(after)}
    return changes


def tree_digest(directory):
    digest = hashlib.sha256()
    count = 0
    total = 0
    directories_seen = 0
    for current, directories, files in os.walk(directory, followlinks=False):
        directories_seen += 1
        require(directories_seen <= 32768)
        directories[:] = sorted(name for name in directories if name != ".git")
        for name in sorted(
            files
            + [name for name in directories if (Path(current) / name).is_symlink()]
        ):
            path = Path(current) / name
            info = path.lstat()
            relative = path.relative_to(directory).as_posix()
            require(info.st_uid == os.geteuid() and "\x00" not in relative)
            if stat.S_ISLNK(info.st_mode):
                value = os.readlink(path)
                require(
                    not Path(value).is_absolute()
                    and (path.parent / value).resolve().is_relative_to(directory)
                )
                identity = "symlink:" + value
            else:
                require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
                identity = file_sha(path)
                total += info.st_size
            count += 1
            require(count <= 131072 and total <= 2**30)
            digest.update(
                (
                    relative
                    + "\0"
                    + str(stat.S_IMODE(info.st_mode))
                    + "\0"
                    + identity
                    + "\n"
                ).encode()
            )
    require(count > 0)
    return {"sha256": digest.hexdigest(), "files": count, "bytes": total}


def configured_zlib(
    name, commit, status, cmake_sha, original_sha, retained_sha, original_absent
):
    require(name == "madler/zlib" and commit == ZLIB_CONFIGURED["commit"])
    require(status == b" D zconf.h\n" and original_absent is True)
    require(cmake_sha == ZLIB_CONFIGURED["cmake_sha256"])
    require(original_sha == retained_sha == ZLIB_CONFIGURED["zconf_sha256"])
    return {
        "version": "1.3.1",
        "recipe": "CMakeLists.txt",
        "recipe_sha256": cmake_sha,
        "tracked_change": " D zconf.h",
        "original_path": "zconf.h",
        "retained_path": "zconf.h.included",
        "original_and_retained_sha256": original_sha,
        "original_path_absent": True,
    }


def inventory_path(relative):
    # Never serialize arbitrary cache names, URLs or Git configuration values.
    parts = []
    for name in relative.parts:
        if name in INVENTORY_NAMES or re.fullmatch(r"[0-9a-f]{32,64}", name):
            parts.append({"public": name})
        else:
            suffix = next(
                (
                    value
                    for value in (".tar.gz", ".tar.xz", ".zip", ".tgz", ".tar")
                    if name.lower().endswith(value)
                ),
                None,
            )
            parts.append(
                {
                    "class": "archive" if suffix else "unknown",
                    "sha256": sha(os.fsencode(name)),
                }
            )
    return parts


def inventory_kind(mode):
    if stat.S_ISLNK(mode):
        return "symlink"
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "regular"
    return "other"


def inventory_target(relative, target):
    # Lexical classification only: never resolve or open a symlink/gitdir target.
    joined = posixpath.normpath(posixpath.join(relative.parent.as_posix(), target))
    inside = (
        not posixpath.isabs(target) and joined != ".." and not joined.startswith("../")
    )
    return {"sha256": sha(os.fsencode(target)), "lexically_within_cache": inside}


def inventory_git(cache, directory):
    result = {"path": inventory_path(directory.relative_to(cache))}
    fd = None
    try:
        relative = directory.relative_to(cache)
        require(len(os.fsencode(relative)) <= INVENTORY_LIMITS["path_bytes"])
        fd = directory_fd(directory)
        info = os.stat(".git", dir_fd=fd, follow_symlinks=False)
        kind = inventory_kind(info.st_mode)
        result["git_entry_type"] = kind
        if kind == "symlink":
            result["target"] = inventory_target(
                relative / ".git", os.readlink(".git", dir_fd=fd)
            )
        elif kind == "regular":
            raw = read_file(directory / ".git", limit=4096)
            result["gitfile_sha256"] = sha(raw)
            if (
                raw.startswith(b"gitdir: ")
                and raw.endswith(b"\n")
                and raw.count(b"\n") == 1
            ):
                result["gitdir"] = inventory_target(
                    relative / ".git", os.fsdecode(raw[8:-1])
                )
            else:
                result["gitfile_format"] = "other"
        elif kind == "directory":
            raw = read_file(directory / ".git" / "HEAD", limit=4096)
            result["head_sha256"] = sha(raw)
            if re.fullmatch(rb"[0-9a-f]{40}\n?", raw):
                result["detached_commit"] = raw.strip().decode("ascii")
            else:
                result["head_format"] = (
                    "symbolic" if raw.startswith(b"ref: ") else "other"
                )
            config = read_file(directory / ".git" / "config", limit=65536)
            result["config_sha256"] = sha(config)
            sections = re.findall(rb'(?m)^\[remote "origin"\]\r?\n([^\[]*)', config)
            urls = (
                re.findall(rb"(?m)^\s*url\s*=\s*(\S+)\s*$", sections[0])
                if len(sections) == 1
                else []
            )
            match = (
                re.fullmatch(
                    rb"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?",
                    urls[0],
                )
                if len(urls) == 1
                else None
            )
            name = match[1].decode("ascii").lower() if match else None
            result["public_identity"] = name if name in DEPENDENCIES else "unknown"
    except (OSError, RuntimeError, ValueError) as error:
        result["metadata_error"] = type(error).__name__
    finally:
        if fd is not None:
            os.close(fd)
    return result


def dependency_inventory(ctx, roots, label="configured-deps"):
    """Private witness only; never selects, removes or repairs discovery roots."""
    require(type(label) is str and re.fullmatch(r"[a-z][a-z0-9_-]{0,47}", label))
    cache = ctx["work"] / "cpm"
    receipt = {
        "diagnostic_only": True,
        "acceptance": False,
        "expected_roots": len(DEPENDENCIES),
        "observed_roots": len(roots),
        "original_walk_error_visibility": "bounded-walk-errors-in-sibling-discovery-receipt",
        "limits": INVENTORY_LIMITS,
        "cache_root_type": "unknown",
        "report_complete": True,
        "errors": [],
        "roots": [],
        "cache_entries": [],
        "report_directories": 0,
        "report_entries": 0,
    }
    # New discovery is bounded to <=33 before a partial over-budget report;
    # its sibling discovery receipt records completion/errors, never historical runs.
    for directory in roots[:33]:
        receipt["roots"].append(inventory_git(cache, directory))
    receipt["root_metadata_complete"] = all(
        "metadata_error" not in item for item in receipt["roots"]
    )
    if len(roots) > 33:
        receipt["report_complete"] = False
        receipt["errors"].append("root-report-budget")

    def walk(fd, relative, depth):
        receipt["report_directories"] += 1
        if receipt["report_directories"] > INVENTORY_LIMITS["directories"]:
            raise RuntimeError("directory-budget")
        with os.scandir(fd) as entries:
            for entry in entries:
                receipt["report_entries"] += 1
                if receipt["report_entries"] > INVENTORY_LIMITS["entries"]:
                    raise RuntimeError("entry-budget")
                path = relative / entry.name
                if len(os.fsencode(path)) > INVENTORY_LIMITS["path_bytes"]:
                    raise RuntimeError("path-budget")
                info = entry.stat(follow_symlinks=False)
                kind = inventory_kind(info.st_mode)
                item = {"path": inventory_path(path), "type": kind}
                receipt["cache_entries"].append(item)
                if kind == "symlink":
                    item["target"] = inventory_target(
                        path, os.readlink(entry.name, dir_fd=fd)
                    )
                elif kind == "directory" and entry.name != ".git":
                    if depth < INVENTORY_LIMITS["depth"]:
                        child = os.open(
                            entry.name,
                            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                            dir_fd=fd,
                        )
                        try:
                            walk(child, path, depth + 1)
                        finally:
                            os.close(child)
                    else:
                        item["contents"] = "outside-shallow-report-depth"

    fd = None
    try:
        receipt["cache_root_type"] = inventory_kind(cache.lstat().st_mode)
        fd = directory_fd(cache)
        walk(fd, Path(), 0)
    except (OSError, RuntimeError, ValueError) as error:
        receipt["report_complete"] = False
        # Fixed classifications only, never exception messages/paths/locals.
        receipt["errors"].append(type(error).__name__)
    finally:
        if fd is not None:
            os.close(fd)
    write_json(ctx["evidence"] / (label + "-inventory.json"), receipt)
    require(receipt["report_complete"])


def discover_dependencies(ctx, label):
    cache = ctx["work"] / "cpm"
    roots, errors = [], []
    counts = {"directories": 0, "entries": 0}
    try:
        checked_directory(cache)
        for current, directories, files in os.walk(
            cache,
            followlinks=False,
            onerror=lambda error: errors.append(type(error).__name__),
        ):
            counts["directories"] += 1
            counts["entries"] += len(directories) + len(files)
            require(counts["directories"] <= 32768 and counts["entries"] <= 131072)
            require(not errors)
            relative = Path(current).relative_to(cache)
            require(len(os.fsencode(relative)) <= 1024)
            require(
                all(
                    len(os.fsencode(relative / name)) <= 1024
                    for name in directories + files
                )
            )
            if ".git" in directories or ".git" in files:
                roots.append(Path(current))
                require(len(roots) <= 33)
            directories[:] = sorted(name for name in directories if name != ".git")
    except (OSError, RuntimeError, ValueError) as error:
        errors.append(type(error).__name__)
    write_json(
        ctx["evidence"] / (label + "-discovery.json"),
        {
            "diagnostic_only": True,
            "acceptance": False,
            "complete": not errors,
            "observed_markers": len(roots),
            "visited": counts,
            "errors": errors[:4],
        },
    )
    dependency_inventory(ctx, roots, label)
    require(not errors)
    return roots


def partition_dependencies(cache, roots):
    require(len(roots) == len(set(roots)))
    primary, nested = {}, []
    for directory in roots:
        relative = directory.relative_to(cache)
        require(".." not in relative.parts and len(relative.parts) >= 2)
        fd = directory_fd(directory)
        try:
            kind = inventory_kind(
                os.stat(".git", dir_fd=fd, follow_symlinks=False).st_mode
            )
        finally:
            os.close(fd)
        if len(relative.parts) == 2:
            package, cache_hash = relative.parts
            require(
                package in PACKAGE_IDENTITIES
                and re.fullmatch(r"[0-9a-f]{40}", cache_hash)
            )
            name = PACKAGE_IDENTITIES[package]
            require(kind == "directory" and name not in primary)
            checked_directory(directory / ".git")
            primary[name] = directory
        else:
            require(kind == "regular")
            nested.append(directory)
    require(set(primary) == DEPENDENCIES)
    expected = {
        primary[name] / contract["path"] for name, contract in NESTED_CONTRACTS.items()
    }
    require(set(nested) == expected and len(nested) == len(expected) == 2)
    return primary


def safe_git_config(raw, identity, worktree=None, contract=None):
    require(isinstance(raw, bytes) and 0 < len(raw) <= 65536 and b"\x00" not in raw)
    values, section = {}, None
    for line in raw.decode("utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("["):
            match = re.fullmatch(
                r'\[(core|advice|remote|branch|submodule)(?: "([A-Za-z0-9_./-]{1,128})")?\]',
                line,
            )
            require(match is not None)
            section = (match[1], match[2])
            require(
                (section[0] in {"core", "advice"} and section[1] is None)
                or section == ("remote", "origin")
                or section[0] == "branch"
                or contract is not None
                and section == ("submodule", contract["path"])
            )
            continue
        require(section is not None)
        match = re.fullmatch(r"([A-Za-z][A-Za-z0-9]*)\s*=\s*([^\r\n]+)", line)
        require(match is not None)
        key, value = (section[0], section[1], match[1].lower()), match[2].strip()
        require(key not in values)
        values[key] = value
        if section[0] == "core":
            allowed = {
                "repositoryformatversion": "0",
                "filemode": "true",
                "bare": "false",
                "logallrefupdates": "true",
                "ignorecase": "false",
            }
            if match[1].lower() == "worktree":
                require(worktree is not None and value == worktree)
            else:
                require(allowed.get(match[1].lower()) == value)
        elif section == ("advice", None):
            require(match[1].lower() == "detachedhead" and value == "false")
        elif section == ("remote", "origin"):
            if match[1].lower() == "url":
                match_url = re.fullmatch(
                    r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?",
                    value,
                )
                require(match_url is not None and match_url[1].lower() == identity)
            else:
                fetch = re.fullmatch(
                    r"\+refs/heads/([A-Za-z0-9_./*-]+):refs/remotes/origin/([A-Za-z0-9_./*-]+)",
                    value,
                )
                require(
                    match[1].lower() == "fetch"
                    and fetch is not None
                    and fetch[1] == fetch[2]
                    and ".." not in value
                )
        elif section[0] == "branch":
            require(section[1] is not None and ".." not in section[1])
            require(
                (match[1].lower() == "remote" and value == "origin")
                or (
                    match[1].lower() == "merge"
                    and re.fullmatch(r"refs/heads/[A-Za-z0-9_./-]+", value)
                    and ".." not in value
                )
            )
        else:
            require(
                contract is not None
                and (
                    (match[1].lower() == "active" and value == "true")
                    or (match[1].lower() == "url" and value == contract["origin"])
                )
            )
    for key, value in (
        ("repositoryformatversion", "0"),
        ("filemode", "true"),
        ("bare", "false"),
    ):
        require(values.get(("core", None, key)) == value)
    require(("remote", "origin", "url") in values)
    require((worktree is None) == (("core", None, "worktree") not in values))


def git_path_exists(path):
    fd = None
    try:
        fd = directory_fd(path.parent)
        os.stat(path.name, dir_fd=fd, follow_symlinks=False)
        return True
    except FileNotFoundError:
        return False
    finally:
        if fd is not None:
            os.close(fd)


def module_namespace(directory, expected):
    modules = directory / "modules"
    if expected is None:
        require(not git_path_exists(modules))
        return
    checked_directory(modules)
    parts = Path(expected).parts
    current = modules
    for part in parts:
        fd = directory_fd(current)
        try:
            with os.scandir(fd) as entries:
                names = [entry.name for entry in entries]
            require(names == [part])
        finally:
            os.close(fd)
        current = current / part
        checked_directory(current)


def packed_refs_safe(raw):
    require(
        isinstance(raw, bytes) and 0 < len(raw) <= 1024 * 1024 and b"\x00" not in raw
    )
    seen, previous = set(), False
    for line in raw.splitlines():
        if line.startswith(b"#"):
            continue
        if line.startswith(b"^"):
            require(previous and re.fullmatch(rb"\^[0-9a-f]{40}", line))
            previous = False
            continue
        match = re.fullmatch(rb"[0-9a-f]{40} (refs/\S+)", line)
        require(match is not None)
        name = match[1]
        require(
            name not in seen
            and name != b"refs/replace"
            and not name.startswith(b"refs/replace/")
        )
        require(b".." not in name and b"//" not in name and b"@{" not in name)
        require(
            not any(byte < 33 or byte == 127 or byte in b"~^:?*[\\" for byte in name)
        )
        require(
            all(
                not part.startswith(b".") and not part.endswith((b".", b".lock"))
                for part in name.split(b"/")
            )
        )
        seen.add(name)
        previous = True


def git_admin_snapshot(directory, nested_path=None):
    checked_directory(directory)
    module_namespace(directory, nested_path)
    for name in (
        "commondir",
        "config.worktree",
        "gitdir",
        "worktrees",
        "info/grafts",
        "objects/info/alternates",
        "objects/info/http-alternates",
        "refs/replace",
    ):
        require(not git_path_exists(directory / name))
    if git_path_exists(directory / "packed-refs"):
        packed_refs_safe(read_file(directory / "packed-refs", limit=1024 * 1024))
    hooks = directory / "hooks"
    if git_path_exists(hooks):
        fd = directory_fd(hooks)
        try:
            with os.scandir(fd) as entries:
                count = 0
                for entry in entries:
                    count += 1
                    require(count <= 64 and entry.name.endswith(".sample"))
                    require(stat.S_ISREG(entry.stat(follow_symlinks=False).st_mode))
        finally:
            os.close(fd)
    # One streamed content digest also freezes refs, index, config, shallow state,
    # object packs and nested admin directories; no subprocess/log per file.
    digest = hashlib.sha256()
    count = total = directories_seen = 0
    errors = []
    for current, directories, files in os.walk(
        directory,
        followlinks=False,
        onerror=lambda error: errors.append(type(error).__name__),
    ):
        directories_seen += 1
        require(not errors and directories_seen <= 32768)
        if Path(current) == directory and nested_path is not None:
            directories[:] = [name for name in directories if name != "modules"]
        directories.sort()
        for name in sorted(directories + files):
            path = Path(current) / name
            info = path.lstat()
            relative = path.relative_to(directory).as_posix()
            require(info.st_uid == os.geteuid() and len(os.fsencode(relative)) <= 1024)
            require(not stat.S_ISLNK(info.st_mode))
            require(not name.endswith(".lock"))
            if stat.S_ISDIR(info.st_mode):
                continue
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1)
            count += 1
            total += info.st_size
            require(count <= 131072 and total <= 2**30)
            digest.update(
                (
                    relative
                    + "\0"
                    + str(stat.S_IMODE(info.st_mode))
                    + "\0"
                    + file_sha(path)
                    + "\n"
                ).encode()
            )
    require(not errors and count > 0)
    return {"sha256": digest.hexdigest(), "files": count, "bytes": total}


def nested_pointer(parent, contract):
    child = parent / contract["path"]
    gitdir = parent / ".git/modules" / contract["path"]
    checked_directory(child)
    checked_directory(gitdir)
    raw = read_file(child / ".git", limit=4096)
    require(raw == ("gitdir: " + os.path.relpath(gitdir, child) + "\n").encode())
    back = os.path.relpath(child, gitdir)
    safe_git_config(
        read_file(gitdir / "config", limit=65536), contract["identity"], back
    )
    return child, gitdir, sha(raw)


def hidden_index_flags(raw):
    require(
        isinstance(raw, bytes) and 0 < len(raw) <= 1024 * 1024 and raw.endswith(b"\x00")
    )
    entries = raw[:-1].split(b"\x00")
    require(len(entries) <= 32768 and len(entries) == len(set(entries)))
    require(
        all(
            item.startswith(b"H ") and len(item) > 2 and b"\n" not in item
            for item in entries
        )
    )
    return sha(raw)


def git_mapping(raw, worktree, gitdir):
    lines = raw.decode("utf-8").splitlines()
    require(len(lines) == 3)
    expected = (gitdir, gitdir, worktree)
    for line, target in zip(lines, expected):
        require(line and "\x00" not in line)
        actual = Path(
            posixpath.normpath(line if line.startswith("/") else str(worktree / line))
        )
        require(actual == target)
        checked_directory(actual)


def nested_manifest(raw, contract):
    require(
        isinstance(raw, bytes) and raw.endswith(b"\x00") and len(raw) <= 1024 * 1024
    )
    links, module = [], []
    for entry in raw[:-1].split(b"\x00"):
        fields = entry.split(b"\t", 1)
        require(len(fields) == 2)
        header = fields[0].split(b" ")
        require(len(header) == 3 and re.fullmatch(rb"[0-9a-f]{40}", header[2]))
        if header[0] == b"160000":
            require(header[1] == b"commit")
            links.append((fields[1], header[2]))
        if fields[1] == b".gitmodules":
            module.append(header)
    require(links == [(contract["path"].encode(), contract["child"].encode())])
    require(module == [[b"100644", b"blob", contract["blob"].encode()]])


def prove_nested(ctx, private_command, label, parent, contract, layout):
    child, gitdir, pointer = nested_pointer(parent, contract)
    require(pointer == layout["pointer_sha256"])
    raw = read_file(parent / ".gitmodules", limit=4096)
    require(raw == base64.b64decode(contract["modules"], validate=True))
    require(
        hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        == contract["blob"]
    )
    nested_manifest(
        git_output(
            ctx,
            private_command,
            label + "-manifest",
            parent,
            "ls-tree",
            "-rz",
            "--full-tree",
            contract["parent"],
        ),
        contract,
    )
    require(
        git_output(
            ctx, private_command, label + "-url", child, "remote", "get-url", "origin"
        ).strip()
        == contract["origin"].encode()
    )
    require(
        git_output(
            ctx, private_command, label + "-head", child, "rev-parse", "HEAD"
        ).strip()
        == contract["child"].encode()
    )
    git_mapping(
        git_output(
            ctx,
            private_command,
            label + "-mapping",
            child,
            "rev-parse",
            "--absolute-git-dir",
            "--git-common-dir",
            "--show-toplevel",
        ),
        child,
        gitdir,
    )
    flags = hidden_index_flags(
        git_output(
            ctx, private_command, label + "-flags", child, "ls-files", "-v", "-z"
        )
    )
    require(
        not git_output(
            ctx,
            private_command,
            label + "-clean",
            child,
            "status",
            "--porcelain",
            "--untracked-files=no",
        )
    )
    require(git_admin_snapshot(gitdir) == layout["admin"])
    return {
        **layout,
        "tree": tree_digest(child),
        "index_flags_sha256": flags,
        "commit": contract["child"],
        "identity": contract["identity"],
        "gitmodules_sha256": sha(raw),
        "contract_source_sha256": PUBLIC_CONTRACTS_SHA,
    }


def dependency_proof(ctx, private_command, label):
    roots = discover_dependencies(ctx, label)
    primary = partition_dependencies(ctx["work"] / "cpm", roots)
    require(len(primary) == len(DEPENDENCIES))
    layouts = {}
    # Every primary and nested config is screened before any Git plumbing/status.
    for name, directory in primary.items():
        safe_git_config(
            read_file(directory / ".git/config", limit=65536),
            name,
            contract=NESTED_CONTRACTS.get(name),
        )
        layouts[name] = {
            "git": git_admin_snapshot(
                directory / ".git",
                NESTED_CONTRACTS[name]["path"] if name in NESTED_CONTRACTS else None,
            )
        }
        if name in NESTED_CONTRACTS:
            child, gitdir, pointer = nested_pointer(directory, NESTED_CONTRACTS[name])
            layouts[name]["nested"] = {
                "path": child.relative_to(ctx["work"]).as_posix(),
                "gitdir": gitdir.relative_to(ctx["work"]).as_posix(),
                "pointer_sha256": pointer,
                "admin": git_admin_snapshot(gitdir),
            }
    result = {}
    for index, (expected_name, directory) in enumerate(sorted(primary.items())):
        prefix = label + "-" + str(index)
        remote = (
            git_output(
                ctx,
                private_command,
                prefix + "-url",
                directory,
                "remote",
                "get-url",
                "origin",
            )
            .decode()
            .strip()
        )
        match = re.fullmatch(
            r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?", remote
        )
        require(match is not None)
        name = match[1].lower()
        require(name == expected_name and name in DEPENDENCIES and name not in result)
        commit = (
            git_output(
                ctx, private_command, prefix + "-head", directory, "rev-parse", "HEAD"
            )
            .decode()
            .strip()
        )
        require(re.fullmatch(r"[0-9a-f]{40}", commit))
        if name in NESTED_CONTRACTS:
            require(commit == NESTED_CONTRACTS[name]["parent"])
        if name == "spartanj/efsw":
            require(commit == EFSW_COMMIT)
        git_mapping(
            git_output(
                ctx,
                private_command,
                prefix + "-mapping",
                directory,
                "rev-parse",
                "--absolute-git-dir",
                "--git-common-dir",
                "--show-toplevel",
            ),
            directory,
            directory / ".git",
        )
        index_flags = hidden_index_flags(
            git_output(
                ctx,
                private_command,
                prefix + "-flags",
                directory,
                "ls-files",
                "-v",
                "-z",
            )
        )
        status = git_output(
            ctx,
            private_command,
            prefix + "-clean",
            directory,
            "status",
            "--porcelain",
            "--untracked-files=no",
        )
        configured = None
        if name == "madler/zlib":
            original = git_output(
                ctx,
                private_command,
                prefix + "-zconf-original",
                directory,
                "show",
                "HEAD:zconf.h",
            )
            retained = read_file(directory / "zconf.h.included")
            require(original == retained)
            configured = configured_zlib(
                name,
                commit,
                status,
                sha(read_file(directory / "CMakeLists.txt")),
                sha(original),
                sha(retained),
                not os.path.lexists(directory / "zconf.h"),
            )
        else:
            require(not status)
        result[name] = {
            "commit": commit,
            "path": directory.relative_to(ctx["work"]).as_posix(),
            "tree": tree_digest(directory),
            "head_sha256": file_sha(directory / ".git/HEAD"),
            "git_admin": layouts[name]["git"],
            "index_flags_sha256": index_flags,
        }
        if name in NESTED_CONTRACTS:
            result[name]["nested"] = prove_nested(
                ctx,
                private_command,
                prefix + "-nested",
                directory,
                NESTED_CONTRACTS[name],
                layouts[name]["nested"],
            )
        require(
            git_admin_snapshot(
                directory / ".git",
                NESTED_CONTRACTS[name]["path"] if name in NESTED_CONTRACTS else None,
            )
            == layouts[name]["git"]
        )
        if configured is not None:
            result[name]["configured_source_transform"] = configured
    require(set(result) == DEPENDENCIES)
    return result


def compile_proof(raw):
    entries = json.loads(raw, object_pairs_hook=unique_object)
    require(isinstance(entries, list) and 100 <= len(entries) <= 4096)
    found = {}
    for entry in entries:
        name = next(
            (name for name in SQL_FILES if entry["file"].endswith("/" + name)), None
        )
        if name:
            require(name not in found)
            argv = entry.get("arguments") or shlex.split(entry["command"])
            require("-std=c++23" in argv and "-Werror" in argv and "-O1" in argv)
            require(
                "-fsanitize=address,undefined,float-divide-by-zero" in argv
                and "-fsanitize-recover=all" in argv
                and "-D_GLIBCXX_ASSERTIONS" in argv
                and "-D_GLIBCXX_SANITIZE_VECTOR" in argv
            )
            require(
                not any(
                    x.startswith(("-flto", "-include-pch", "-Wno-error")) for x in argv
                )
            )
            found[name] = sha(json.dumps(argv, separators=(",", ":")).encode())
    require(set(found) == set(SQL_FILES))
    return found


def link_proof(raw, archive):
    matches = []
    for line in raw.decode().splitlines():
        for clause in line.split("&&"):
            argv = shlex.split(clause)
            if "-o" in argv and Path(argv[argv.index("-o") + 1]).name == "xi_test":
                require(str(archive) in argv and argv.count(str(archive)) == 1)
                require(
                    "-fsanitize=address,undefined,float-divide-by-zero" in argv
                    and "-fsanitize-recover=all" in argv
                )
                require(
                    not any(
                        "libluajit" in value and value != str(archive) for value in argv
                    )
                )
                matches.append(sha(clause.encode()))
    require(len(matches) == 1)
    return matches[0]


def verify_native(ctx, private_command, label, dependencies):
    binary = ctx["program"] / "xi_test"
    require(prefix(binary, 4) == b"\x7fELF")
    dynamic = run(
        ctx,
        private_command,
        label + "-dynamic",
        ["/usr/bin/readelf", "--dynamic", str(binary)],
        capture=True,
    )["stdout"]
    require(b"libluajit" not in dynamic.lower())
    selector = 'set -euo pipefail; /usr/bin/llvm-nm-22 --defined-only --extern-only --just-symbol-name "$1" | /usr/bin/awk \'/^(__asan_init|lua_newstate|lua_pcall)$/ { print; next } /^__ubsan_handle_/ { u=1 } END { if (u) print "__ubsan_handle_family_present" }\''
    table = run(
        ctx,
        private_command,
        label + "-symbols",
        ["/bin/bash", "-c", selector, "symbol-selector", str(binary)],
        capture=True,
    )["stdout"].splitlines()
    require(
        set(table)
        == {
            b"__asan_init",
            b"__ubsan_handle_family_present",
            b"lua_newstate",
            b"lua_pcall",
        }
        and len(table) == 4
    )
    archive = ctx["work"] / "luajit-prefix/lib/libluajit-5.1.a"
    require(read_file(archive, limit=64 * 1024 * 1024).startswith(b"!<arch>\n"))
    undefined = run(
        ctx,
        private_command,
        label + "-lua-symbols",
        ["/usr/bin/llvm-nm-22", "--undefined-only", str(archive)],
        capture=True,
    )["stdout"]
    require(b"__asan_" in undefined)
    cache = read_file(ctx["work"] / "build/CMakeCache.txt").decode()
    require(
        "CMAKE_BUILD_TYPE:STRING=ASAN\n" in cache
        and "PCH_ENABLE:BOOL=OFF\n" in cache
        and "WARNINGS_AS_ERRORS:BOOL=TRUE\n" in cache
    )
    require("LuaJIT_LIBRARY:FILEPATH=" + str(archive) + "\n" in cache)
    commands = read_file(ctx["work"] / "build/compile_commands.json")
    links = run(
        ctx,
        private_command,
        label + "-link-commands",
        [
            "/usr/bin/ninja",
            "-C",
            str(ctx["work"] / "build"),
            "-t",
            "commands",
            "xi_test",
        ],
    )
    link = link_proof(
        read_file(links["log"], private=True, limit=32 * 1024 * 1024), archive
    )
    proof = {
        "binary_sha256": file_sha(binary),
        "luajit_archive_sha256": file_sha(archive),
        "cmake_cache_sha256": sha(cache.encode()),
        "compile_commands_sha256": sha(commands),
        "link_command_sha256": link,
        "link_commands_sha256": file_sha(links["log"]),
        "build_ninja_sha256": file_sha(ctx["work"] / "build/build.ninja"),
        "rules_ninja_sha256": file_sha(ctx["work"] / "build/CMakeFiles/rules.ninja"),
        "luajit_head_sha256": file_sha(ctx["work"] / "luajit/.git/HEAD"),
        "sql_compile_commands": compile_proof(commands),
        "sql_source_sha256": source_proof(
            ctx, private_command, label + "-source", True
        ),
        "dependencies": dependencies,
    }
    require(file_sha(ctx["work"] / "build/src/test/xi_test") == proof["binary_sha256"])
    verify_frozen(ctx, private_command, label + "-frozen", proof)
    return proof


def verify_frozen(ctx, private_command, label, proof):
    files = {
        "binary_sha256": ctx["program"] / "xi_test",
        "luajit_archive_sha256": ctx["work"] / "luajit-prefix/lib/libluajit-5.1.a",
        "cmake_cache_sha256": ctx["work"] / "build/CMakeCache.txt",
        "compile_commands_sha256": ctx["work"] / "build/compile_commands.json",
        "build_ninja_sha256": ctx["work"] / "build/build.ninja",
        "rules_ninja_sha256": ctx["work"] / "build/CMakeFiles/rules.ninja",
        "luajit_head_sha256": ctx["work"] / "luajit/.git/HEAD",
    }
    require(all(file_sha(path) == proof[name] for name, path in files.items()))
    require(file_sha(ctx["work"] / "build/src/test/xi_test") == proof["binary_sha256"])
    require(
        source_proof(ctx, private_command, label + "-source", True)
        == proof["sql_source_sha256"]
    )
    require(set(proof["dependencies"]) == DEPENDENCIES)
    for name, item in proof["dependencies"].items():
        path = ctx["work"] / item["path"]
        require(path.is_relative_to(ctx["work"] / "cpm") and ".." not in path.parts)
        require(
            tree_digest(path) == item["tree"]
            and file_sha(path / ".git/HEAD") == item["head_sha256"]
        )
        require(
            git_admin_snapshot(
                path / ".git",
                NESTED_CONTRACTS[name]["path"] if name in NESTED_CONTRACTS else None,
            )
            == item["git_admin"]
        )
        if name in NESTED_CONTRACTS:
            contract = NESTED_CONTRACTS[name]
            child, gitdir, pointer = nested_pointer(path, contract)
            nested = item["nested"]
            require(
                child == ctx["work"] / nested["path"]
                and gitdir == ctx["work"] / nested["gitdir"]
            )
            require(
                pointer == nested["pointer_sha256"]
                and sha(read_file(path / ".gitmodules", limit=4096))
                == nested["gitmodules_sha256"]
            )
            require(
                tree_digest(child) == nested["tree"]
                and git_admin_snapshot(gitdir) == nested["admin"]
            )
        else:
            require("nested" not in item)


def sql(ctx, private_command, label, query, capture=False):
    return run(
        ctx,
        private_command,
        label,
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/mariadb",
            "--no-defaults",
            "--protocol=SOCKET",
            "--socket=/run/mysqld/mysqld.sock",
            "--batch",
            "--skip-column-names",
            "--execute",
            query,
        ],
        capture=capture,
    )


def database_identity(ctx, private_command, label, empty):
    identity = (
        sql(
            ctx,
            private_command,
            label + "-identity",
            "SELECT @@bind_address,@@port,@@socket,@@hostname;",
            True,
        )["stdout"]
        .decode()
        .strip()
        .split("\t")
    )
    require(
        len(identity) == 4
        and identity[:3] == ["127.0.0.1", "3306", "/run/mysqld/mysqld.sock"]
    )
    require(identity[3] == os.uname().nodename)
    inventory = (
        sql(ctx, private_command, label + "-schemas", "SHOW DATABASES;", True)["stdout"]
        .decode()
        .splitlines()
    )
    require(
        set(inventory)
        == {"information_schema", "mysql", "performance_schema", "sys", DATABASE}
    )
    query = (
        " UNION ALL ".join(
            "SELECT '" + table + "',COUNT(*) FROM " + DATABASE + "." + table
            for table in PRIVATE_TABLES
        )
        + ";"
    )
    rows = (
        sql(ctx, private_command, label + "-rows", query, True)["stdout"]
        .decode()
        .splitlines()
    )
    parsed = {}
    for line in rows:
        table, count = line.split("\t")
        require(
            table in PRIVATE_TABLES
            and table not in parsed
            and re.fullmatch(r"[0-9]+", count)
        )
        parsed[table] = int(count)
    require(
        set(parsed) == set(PRIVATE_TABLES) and (not empty or not any(parsed.values()))
    )
    return {
        "database": DATABASE,
        "host": "127.0.0.1",
        "port": 3306,
        "socket": "/run/mysqld/mysqld.sock",
        "private_counts": parsed,
    }


def native_env(ctx):
    program = str(ctx["program"])
    evidence = str(ctx["evidence"])
    return child_env(
        ctx,
        {
            "XI_NETWORK_SQL_HOST": "127.0.0.1",
            "XI_NETWORK_SQL_PORT": "3306",
            "XI_NETWORK_SQL_DATABASE": DATABASE,
            "XI_NETWORK_SQL_LOGIN": DB_USER,
            "XI_NETWORK_SQL_PASSWORD": DB_PASSWORD,
            "XI_NETWORK_MAP_PORT": "54230",
            "ASAN_OPTIONS": "halt_on_error=0:handle_abort=1:strict_string_checks=1:check_initialization_order=1:strict_init_order=1:quarantine_size_mb=2048:strip_path_prefix="
            + program
            + "/:log_path="
            + evidence
            + "/sanitizer.log",
            "UBSAN_OPTIONS": "print_stacktrace=1:report_error_type=1:handle_abort=1:strip_path_prefix="
            + program
            + "/:suppressions="
            + program
            + "/sanitizers/ubsan.supp:log_path="
            + evidence
            + "/sanitizer.log",
            "ASAN_SYMBOLIZER_PATH": "/usr/bin/llvm-symbolizer-22",
            "UBSAN_SYMBOLIZER_PATH": "/usr/bin/llvm-symbolizer-22",
        },
    )


def stage_and_build(ctx, private_command):
    ctx = normalize_context(ctx)
    validate_context(ctx)
    require(not os.path.lexists(ctx["evidence"] / "build.started.json"))
    write_json(
        ctx["evidence"] / "build.started.json",
        {
            "source": SOURCE,
            "nonce": NONCE,
            "diagnostic_only": True,
            "acceptance": False,
        },
    )
    for name in ("home", "tmp", "cpm"):
        (ctx["work"] / name).mkdir(mode=0o700)
    initial = source_proof(ctx, private_command, "initial-source", False)
    packages = [
        "binutils-dev",
        "build-essential",
        "ca-certificates",
        "clang-22",
        "clang-tidy-22",
        "cmake",
        "git",
        "libclang-rt-22-dev",
        "libdwarf-dev",
        "libluajit-5.1-dev",
        "libmariadb-dev-compat",
        "libssl-dev",
        "libzmq3-dev",
        "llvm-22-dev",
        "luajit",
        "mariadb-client",
        "mariadb-server",
        "ninja-build",
        "pkg-config",
        "python3-dev",
        "python3-venv",
        "tzdata",
        "zlib1g-dev",
        "libzstd-dev",
    ]
    install_env = child_env(ctx, {"DEBIAN_FRONTEND": "noninteractive"})
    run(
        ctx,
        private_command,
        "apt-update",
        ["/usr/bin/sudo", "-n", "/usr/bin/apt-get", "update"],
        timeout=900,
        env=install_env,
    )
    run(
        ctx,
        private_command,
        "apt-install",
        [
            "/usr/bin/sudo",
            "-n",
            "/usr/bin/apt-get",
            "install",
            "--assume-yes",
            "--no-install-recommends",
            "--quiet",
            *packages,
        ],
        timeout=1200,
        env=install_env,
    )
    versions = {}
    for label, argv in (
        ("os-version", ["/usr/bin/lsb_release", "-a"]),
        ("compiler-version", ["/usr/bin/clang++-22", "--version"]),
        ("cmake-version", ["/usr/bin/cmake", "--version"]),
        ("ninja-version", ["/usr/bin/ninja", "--version"]),
        ("python-version", [sys.executable, "--version"]),
        ("packages", ["/usr/bin/dpkg-query", "-W"]),
    ):
        versions[label] = run(ctx, private_command, label, argv, capture=True)[
            "stdout"
        ].decode()
    require("Ubuntu" in versions["os-version"] and "26.04" in versions["os-version"])
    require(re.search(r"\bclang version 22\.", versions["compiler-version"]))
    require(re.search(r"\bPython 3\.14\.", versions["python-version"]))
    versions["compiler_path"] = str(Path("/usr/bin/clang++-22").resolve())
    versions["compiler_sha256"] = file_sha(Path(versions["compiler_path"]))
    venv = ctx["work"] / "venv"
    run(ctx, private_command, "python-venv", [sys.executable, "-m", "venv", str(venv)])
    python = str(venv / "bin/python")
    run(
        ctx,
        private_command,
        "pip-bootstrap",
        [python, "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"],
        timeout=600,
    )
    run(
        ctx,
        private_command,
        "pip-requirements",
        [
            python,
            "-m",
            "pip",
            "install",
            "-r",
            str(ctx["program"] / "tools/requirements.txt"),
            "jinja2",
            "jsonschema",
            "ruamel.yaml",
        ],
        timeout=900,
    )
    versions["python_packages"] = run(
        ctx,
        private_command,
        "pip-versions",
        [python, "-m", "pip", "freeze"],
        capture=True,
    )["stdout"].decode()
    luajit = ctx["work"] / "luajit"
    run(
        ctx,
        private_command,
        "luajit-clone",
        [
            "/usr/bin/git",
            "clone",
            "--depth",
            "1",
            "--branch",
            "v2.1",
            "https://github.com/LuaJIT/LuaJIT.git",
            str(luajit),
        ],
        timeout=300,
    )
    commit = (
        git_output(ctx, private_command, "luajit-head", luajit, "rev-parse", "HEAD")
        .decode()
        .strip()
    )
    require(re.fullmatch(r"[0-9a-f]{40}", commit))
    run(
        ctx,
        private_command,
        "luajit-detach",
        [
            "/usr/bin/git",
            "--no-optional-locks",
            "-C",
            str(luajit),
            "checkout",
            "--detach",
            commit,
        ],
    )
    require(read_file(luajit / ".git/HEAD").strip() == commit.encode())
    versions["luajit_commit"] = commit
    versions["luajit_recipe"] = {
        "buildmode": "static",
        "system_allocator": True,
        "c_flags": "-fsanitize=address -fsanitize-recover=address -fno-omit-frame-pointer",
    }
    write_json(ctx["evidence"] / "toolchain.before-build.json", versions)
    run(
        ctx,
        private_command,
        "luajit-build",
        [
            "/usr/bin/make",
            "-C",
            str(luajit),
            "-j2",
            "BUILDMODE=static",
            "XCFLAGS=-DLUAJIT_USE_SYSMALLOC",
            "HOST_CC=/usr/bin/clang-22",
            "CC=/usr/bin/clang-22 -fsanitize=address -fsanitize-recover=address -fno-omit-frame-pointer",
        ],
        timeout=900,
    )
    prefix = ctx["work"] / "luajit-prefix"
    run(
        ctx,
        private_command,
        "luajit-install",
        [
            "/usr/bin/make",
            "-C",
            str(luajit),
            "install",
            "BUILDMODE=static",
            "PREFIX=" + str(prefix),
        ],
        timeout=300,
    )
    changes = instrument_program(ctx)
    build = ctx["work"] / "build"
    env = child_env(
        ctx,
        {
            "CC": "/usr/bin/clang-22",
            "CXX": "/usr/bin/clang++-22",
            "CPM_SOURCE_CACHE": str(ctx["work"] / "cpm"),
            "PATH": str(venv / "bin") + ":" + ctx["env"]["PATH"],
        },
    )
    run(
        ctx,
        private_command,
        "configure",
        [
            "/usr/bin/cmake",
            "-G",
            "Ninja",
            "-S",
            str(ctx["program"]),
            "-B",
            str(build),
            "--fresh",
            "-DCMAKE_BUILD_TYPE=ASAN",
            "-DENABLE_CLANG_TIDY=OFF",
            "-DTRACY_ENABLE=OFF",
            "-DPCH_ENABLE=OFF",
            "-DWARNINGS_AS_ERRORS=TRUE",
            "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            "-DCACHE_OPTION=env",
            "-DCACHE_BINARY:FILEPATH=/usr/bin/env",
            "-DPython_EXECUTABLE:FILEPATH=" + python,
            "-DLuaJIT_LIBRARY:FILEPATH=" + str(prefix / "lib/libluajit-5.1.a"),
        ],
        timeout=1200,
        env=env,
    )
    dependencies = dependency_proof(ctx, private_command, "configured-deps")
    write_json(ctx["evidence"] / "dependencies.before-build.json", dependencies)
    run(
        ctx,
        private_command,
        "build",
        [
            "/usr/bin/cmake",
            "--build",
            str(build),
            "--target",
            "xi_test",
            "--parallel",
            "2",
        ],
        timeout=5400,
        env=env,
    )
    proof = verify_native(ctx, private_command, "built", dependencies)
    require(read_file(luajit / ".git/HEAD").strip() == commit.encode())
    # Only the fresh hosted runner's loopback DB is eligible; never import data.
    run(
        ctx,
        private_command,
        "database-start",
        ["/usr/bin/sudo", "-n", "/usr/sbin/service", "mariadb", "start"],
        timeout=120,
    )
    schemas = (
        sql(ctx, private_command, "database-pristine", "SHOW DATABASES;", True)[
            "stdout"
        ]
        .decode()
        .splitlines()
    )
    require(
        set(schemas) == {"information_schema", "mysql", "performance_schema", "sys"}
    )
    identity = (
        sql(
            ctx,
            private_command,
            "database-loopback",
            "SELECT @@bind_address,@@port,@@socket,@@hostname;",
            True,
        )["stdout"]
        .decode()
        .strip()
        .split("\t")
    )
    require(
        identity
        == ["127.0.0.1", "3306", "/run/mysqld/mysqld.sock", os.uname().nodename]
    )
    sql(
        ctx,
        private_command,
        "database-create",
        "CREATE DATABASE "
        + DATABASE
        + " CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
        "CREATE USER '" + DB_USER + "'@'127.0.0.1' IDENTIFIED BY '" + DB_PASSWORD + "';"
        "GRANT ALL PRIVILEGES ON " + DATABASE + ".* TO '" + DB_USER + "'@'127.0.0.1';",
    )
    run(
        ctx,
        private_command,
        "database-initialize",
        [python, str(ctx["program"] / "tools/dbtool.py"), "update"],
        timeout=1200,
        env=native_env(ctx),
    )
    before = database_identity(ctx, private_command, "database-ready", True)
    receipt = {
        "schema": "hosted-private-asan-build-v1",
        "source": SOURCE,
        "nonce": NONCE,
        "passed": True,
        "diagnostic_only": True,
        "acceptance": False,
        "historical_environment_equivalence": False,
        "toolchain": versions,
        "initial_sql_sha256": initial,
        "instrumentation": changes,
        "recipe_sha256": RECIPE_SHA,
        "header_sha256": HEADER_SHA,
        "native_proof": proof,
        "database_before": before,
        "expected_cpp": 103,
        "expected_executed": 1,
        "expected_filtered": 19,
    }
    write_json(ctx["evidence"] / "build.receipt.json", receipt)
    return receipt


def check_report(value):
    results = value["results"]
    summary = results["summary"]
    require(
        all(
            type(summary[name]) is int
            for name in (
                "tests",
                "passed",
                "skipped",
                "failed",
                "flaky",
                "pending",
                "other",
            )
        )
    )
    require(summary["tests"] == summary["passed"] == 1 and summary["skipped"] == 19)
    require(all(summary[name] == 0 for name in ("failed", "flaky", "pending", "other")))
    tests = results["tests"]
    require(len(tests) == 1)
    case = tests[0]
    require(
        case["name"] == CASE and case["suite"] == SUITE and case["filePath"] == FILE
    )
    require(
        case["status"] == "passed"
        and case["flaky"] is False
        and type(case["retries"]) is int
        and case["retries"] == 0
        and case["retryAttempts"] == []
    )
    return {
        "cpp_cases": 103,
        "lua_executed": 1,
        "lua_filtered": 19,
        "native_retries": 0,
    }


def measurement(raw):
    prefix = b"MOCHI_SQL_TIMING_V1 "
    records = [
        line[len(prefix) :]
        for line in raw.splitlines(keepends=True)
        if line.startswith(prefix)
    ]
    require(
        len(records) == 1
        and len(records[0]) < 1024
        and records[0].endswith(b"\n")
        and not records[0].endswith(b"\r\n")
    )
    record = json.loads(records[0], object_pairs_hook=unique_object)
    fields = {
        "diagnostic_only",
        "acceptance",
        "query_tag",
        "thread_id",
        "closed",
        "resource_valid",
        "phase_mask",
        "raw_query_bracket_ns",
        "execute_ns",
        "schema_ns",
        "fetch_ns",
        "rows",
        "rows_recorded",
        "user_cpu_ns",
        "system_cpu_ns",
        "voluntary_switches",
        "involuntary_switches",
        "phase_clock_samples",
        "resource_samples",
    }
    require(
        set(record) == fields
        and record["diagnostic_only"] is True
        and record["acceptance"] is False
        and record["query_tag"] == "load_job_points_first"
    )
    require(
        all(
            type(record[name]) is int
            for name in fields - {"diagnostic_only", "acceptance", "query_tag"}
        )
    )
    require(
        record["thread_id"] > 0
        and record["closed"] == record["resource_valid"] == record["rows_recorded"] == 1
    )
    require(
        record["phase_mask"] == 7
        and record["phase_clock_samples"] == 6
        and record["resource_samples"] == 2
    )
    require(0 <= record["rows"] <= 1000000)
    require(
        all(
            0 <= record[name] <= 60000000000
            for name in (
                "raw_query_bracket_ns",
                "execute_ns",
                "schema_ns",
                "fetch_ns",
                "user_cpu_ns",
                "system_cpu_ns",
            )
        )
    )
    require(
        sum(record[name] for name in ("execute_ns", "schema_ns", "fetch_ns"))
        <= record["raw_query_bracket_ns"]
    )
    require(
        all(
            0 <= record[name] <= 10000000
            for name in ("voluntary_switches", "involuntary_switches")
        )
    )
    return record


def native_command(ctx):
    return [
        "/usr/bin/prlimit",
        "--fsize=16777216:16777216",
        "--core=0:0",
        "--",
        str(ctx["program"] / "xi_test"),
        "--keep-going",
        "--retry",
        "0",
        "--file",
        "^" + re.escape(FILE) + "$",
        "--filter",
        "^" + re.escape(SUITE + "::" + CASE) + "$",
        "--output",
        str(ctx["evidence"] / "report.ctrf.json"),
        "--log",
        str(ctx["evidence"] / "native.log"),
    ]


def evidence_budget(ctx, before_native=False):
    count = 0
    total = 0
    for path in ctx["evidence"].iterdir():
        info = path.lstat()
        require(
            stat.S_ISREG(info.st_mode)
            and info.st_uid == os.geteuid()
            and info.st_nlink == 1
            and stat.S_IMODE(info.st_mode) == 0o600
        )
        require(info.st_size <= 64 * 1024 * 1024)
        count += 1
        total += info.st_size
    # Reserve 56 entries and 88MiB for native/report/sanitizer/finalization.
    require(
        count <= (200 if before_native else 256)
        and total <= (40 if before_native else 128) * 1024 * 1024
    )
    return {"files": count, "bytes": total}


def native_diagnostics(channels):
    target = (
        "SELECT charid, jobid, capacity_points, job_points, "
        "job_points_spent, jptype0, jptype1, jptype2, "
        "jptype3, jptype4, jptype5, jptype6, "
        "jptype7, jptype8, jptype9 "
        "FROM char_job_points WHERE charid = ? ORDER BY jobid ASC"
    )
    ansi = re.compile(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\))")
    tag = re.compile(r"\[\s*(erro(?:r)?|crit(?:ical)?|fatal|warn(?:ing)?)\s*\]", re.I)
    patterns = (
        re.compile(
            r"^\[\d{2}:\d{2}:\d{2}\]\[(?P<level>[A-Za-z]+)\]\[(?P<source>[^]\r\n]+:\d+)\] (?P<message>.*)$"
        ),
        re.compile(
            r"^\[\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}:\d{3}\]\[test\]\[(?P<level>[A-Za-z]+)\] (?P<message>.*?) \((?P<source>[^\s]+:\d+)\)$"
        ),
    )
    warnings = []
    for channel, text in channels.items():
        require(isinstance(text, str))
        for line in text.splitlines():
            clean = ansi.sub("", line)
            prefix = next(
                (match for pattern in patterns if (match := pattern.fullmatch(clean))),
                None,
            )
            severity = tag.search(clean)
            if (
                prefix
                and prefix["level"].lower()
                in {"info", "debu", "debug", "trac", "trace", "lua"}
                and not severity
            ):
                continue
            if not prefix and not severity:
                require(
                    not re.search(
                        r"(?:(?:^|\b)(?:WARNING|ERROR|FATAL|CRITICAL):|runtime error:|terminate called|Segmentation fault)",
                        clean,
                        re.I,
                    )
                )
                continue
            require(
                prefix is not None and prefix["level"].lower() in {"warn", "warning"}
            )
            function, _, line_number = prefix["source"].rpartition(":")
            # The exact reviewed include adds two lines before the unchanged emitter.
            require(function.strip() == "operator()" and line_number == "76")
            message = re.fullmatch(
                r"SQL query took ([0-9]{1,5})ms: " + re.escape(target),
                prefix["message"],
            )
            require(message is not None and 100 < int(message[1]) <= 250)
            warnings.append(
                {
                    "channel": channel,
                    "duration_ms": int(message[1]),
                    "emitter_line": 76,
                    "emitter": "operator()",
                    "raw_sha256": sha(clean.encode()),
                }
            )
    return {
        "unexpected_errors_or_warnings": 0,
        "observed_target_sql_warning_records": warnings,
        "historical_failure_reclassified": False,
        "warning_is_acceptance": False,
    }


def observe_once(ctx, private_command):
    ctx = normalize_context(ctx)
    validate_context(ctx)
    receipt = json.loads(
        read_file(ctx["evidence"] / "build.receipt.json", private=True),
        object_pairs_hook=unique_object,
    )
    require(
        receipt["source"] == SOURCE
        and receipt["nonce"] == NONCE
        and receipt["passed"] is True
        and receipt["acceptance"] is False
    )
    require(
        receipt["recipe_sha256"] == RECIPE_SHA
        and receipt["header_sha256"] == HEADER_SHA
    )
    verify_frozen(ctx, private_command, "pre-observation", receipt["native_proof"])
    before = database_identity(ctx, private_command, "pre-observation", True)
    require(before == receipt["database_before"])
    budget = evidence_budget(ctx, before_native=True)
    before_names = {path.name for path in ctx["evidence"].iterdir()}
    resource = {
        "tool": str(Path("/usr/bin/prlimit").resolve()),
        "tool_sha256": file_sha(Path("/usr/bin/prlimit").resolve()),
        "file_size_soft_bytes": 16777216,
        "file_size_hard_bytes": 16777216,
        "core_soft_bytes": 0,
        "core_hard_bytes": 0,
    }
    write_json(
        ctx["evidence"] / "observation.started.json",
        {
            "source": SOURCE,
            "nonce": NONCE,
            "run_id": os.environ["GITHUB_RUN_ID"],
            "run_attempt": 1,
            "native_attempts": 1,
            "native_retries": 0,
            "diagnostic_only": True,
            "acceptance": False,
            "budget_before": budget,
            "native_resource_contract": resource,
            "native_resource_contract_sha256": sha(
                json.dumps(resource, sort_keys=True).encode()
            ),
        },
    )
    outcome = {
        "schema": "hosted-private-asan-observation-v1",
        "passed": False,
        "diagnostic_only": True,
        "acceptance": False,
        "source": SOURCE,
        "native_attempts": 1,
        "native_retries": 0,
        "returncode": None,
        "historical_cause_established": False,
        "historical_failure_reclassified": False,
    }
    try:
        result = run(
            ctx,
            private_command,
            "one-native-observation",
            native_command(ctx),
            timeout=1800,
            env=native_env(ctx),
            check=False,
        )
        outcome["returncode"] = result["returncode"]
        raw = read_file(result["log"], private=True, limit=32 * 1024 * 1024)
        require(result["returncode"] == 0)
        require(
            len(re.findall(rb"All tests passed \([^\n]+ in 103 test cases\)", raw)) == 1
        )
        report = json.loads(
            read_file(ctx["evidence"] / "report.ctrf.json", private=True),
            object_pairs_hook=unique_object,
        )
        outcome.update(check_report(report))
        outcome["measurement"] = measurement(raw)
        native_log = ctx["evidence"] / "native.log"
        require(native_log.is_file())
        output = report["results"]["tests"][0]["stdout"]
        require(
            isinstance(output, list) and all(isinstance(line, str) for line in output)
        )
        outcome["diagnostics"] = native_diagnostics(
            {
                "console": raw.decode(),
                "native_log": read_file(
                    native_log, private=True, limit=8 * 1024 * 1024
                ).decode(),
                "ctrf_case": "\n".join(output),
            }
        )
        require(not list(ctx["evidence"].glob("sanitizer.log.*")))
        outcome["passed"] = True
    except BaseException as error:
        # Type only; the owning controller encrypts every raw file even on failure.
        outcome["failure_type"] = type(error).__name__
    finally:
        post = {}
        for label, action in (
            (
                "database_empty",
                lambda: require(
                    database_identity(ctx, private_command, "final-database", True)
                    == before
                ),
            ),
            (
                "source_and_binary_unchanged",
                lambda: verify_frozen(
                    ctx, private_command, "final-native", receipt["native_proof"]
                ),
            ),
        ):
            try:
                action()
                post[label] = True
            except BaseException:
                post[label] = False
        outcome["postflight"] = post
        outcome["passed"] = outcome["passed"] and all(post.values())
        try:
            after_names = {path.name for path in ctx["evidence"].iterdir()}
            sanitizer = {
                name
                for name in after_names
                if re.fullmatch(r"sanitizer\.log\.[1-9][0-9]*", name)
            }
            require(len(sanitizer) <= 1)
            permitted = (
                before_names
                | ctx.get("_logs", set())
                | sanitizer
                | {
                    "observation.started.json",
                    "observation.outcome.json",
                    "report.ctrf.json",
                    "native.log",
                }
            )
            require(after_names <= permitted)
            outcome["budget_after"] = evidence_budget(ctx)
        except BaseException:
            outcome["passed"] = False
            outcome["budget_after"] = {"passed": False}
        write_json(ctx["evidence"] / "observation.outcome.json", outcome)
    return outcome
