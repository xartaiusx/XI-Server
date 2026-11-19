# EnemyBar for Mochirii

Based on the [official EnemyBar addon](https://github.com/Windower/Lua/tree/15ddc1e36b3806c325e29fedd550b2977828d4d5/addons/enemybar)
at Windower/Lua commit `15ddc1e36b3806c325e29fedd550b2977828d4d5`.
The original BSD 3-Clause copyright notice and the three original textures are included.
This adaptation renders the selected monster's EnemyBar above the Mochirii hotbars.

The addon shows HP, MP and TP for the selected monster. Fresh private replies provide
exact values and visible statuses for Twills. While no fresh values are available, each
field shows a dash placeholder and the bar follows the native HP proportion.
The addon reuses the installed XivParty status textures. Missing textures show their icon IDs.

The Windower packet library sends the reserved request directly to the Mochirii server
without opening chat input. The server consumes the request privately. The addon reads
only verified native replies and does not send requests in Mordion Gaol.

Restore by overlaying these files and the corresponding tracked startup line onto the
current Windower golden state. All texture and Lua files must be taken from the same
manifest. Install XivParty as documented in the existing Mochirii portable restore guide.
