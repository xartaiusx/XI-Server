# EnemyBar for Mochirii

Based on the [official EnemyBar addon](https://github.com/Windower/Lua/tree/15ddc1e36b3806c325e29fedd550b2977828d4d5/addons/enemybar)
at Windower/Lua commit `15ddc1e36b3806c325e29fedd550b2977828d4d5`.
The original BSD 3-Clause copyright notice and the three original textures are included.
This adaptation renders the selected monster's EnemyBar above the Mochirii hotbars.

Without a fresh Mochirii reply, the addon shows the selected monster's native HP percentage.
With a fresh reply it shows exact HP, MP, TP and visible statuses for Twills. The addon
reuses the already installed XivParty status textures. Missing textures show their icon IDs.
The protocol sends ordinary local chat and reads only verified native system packets.

Restore by overlaying these files and the corresponding tracked startup line onto the
current Windower golden state. All texture and Lua files must be taken from the same
manifest. Install XivParty as documented in the existing Mochirii portable restore guide.
