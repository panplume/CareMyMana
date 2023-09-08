# CareMyMana

![CareMyMana rune](/CareMyMana.png)

Display an icon for the recommended potion to drink in order to restore your mana. If sound is on (*/cmm cry*), it will play every 30s as long as you are missing mana and a potion can be used. If all potions are on cooldown, display the one with the shortest cooldown (no sound will be played). If no potion is available or a major mana regen event is running (Mana Tide/Trinket/Innervate/Symbol of Hope), display nothing.

Editing the source is required to:

1. Change the sound file
1. Change the delay between sound
1. Add/Remove potions

# Command line usage (/cmm or /caremymana)

| Command      | Description                                                |
|--------------|------------------------------------------------------------|
| /cmm lock    | Prevent the icon to be moved                               |
| /cmm unlock  | Allow the icon to be moved                                 |
| /cmm enable  | Enable the addon                                           |
| /cmm disable | Disable the addon                                          |
| /cmm cry     | Play a sound when you can drink the recommended potion     |
| /cmm stfu    | No sound (default)                                         |


# Command line example:

```
/cmm unlock
```

then cast some spells to trigger the icon to display and move it (displaying a default icon on unlock is a planned feature, for the futur, one day, maybe, please).
