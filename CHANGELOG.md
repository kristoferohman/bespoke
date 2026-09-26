# Changelog

## 1.5.0
- Option to color the whole button red when out of range and blue when out of mana (Blizzard only reddens the keybind when out of range). Off by default; per profile. In the options window, or `/bespoke color on | off`.

## 1.4.3
- Releases now publish to CurseForge automatically. No change in game.

## 1.4.2
- Faded bars dim to 40% while bars are unlocked instead of staying fully visible, so a fade setting is visible immediately.
- `/bespoke which` reports the bar's fade setting, lock state and opacity.

## 1.4.1
- Fix: stance buttons beyond your number of forms appeared at Blizzard's stance bar position after using Edit Mode. They're now parked out of sight.

## 1.4.0
- Scale goes down to 40%.
- Fade until mouseover, per bar: appears instantly, fades out over 0.2s. Works in combat.
- `/bespoke which` names the frame under the mouse and whether Bespoke owns it.

## 1.3.2
- Pet and stance bars preview all 10 slots while unlocked, so they can be arranged on any character.
- Fix: `/bespoke lock` during combat re-registered the pet bar's visibility driver (a blocked action).

## 1.3.1
- Fix: Blizzard micro menu errors (`GetEdgeButton`) when taking its buttons, and again on Edit Mode layout.

## 1.3.0
- Pet bar, stance bar, bag bar and micro menu, reusing Blizzard's buttons.
- Padding down to −2; grow up or down; lay out by columns or by rows.
- Positions stored in screen units, so scaling doesn't drift (older profiles migrate once).
- Options show which characters use a profile; choose the profile new characters start on.

## 1.2.0
- Renamed to Bespoke (previously BartenderBespoke; settings don't carry over from the old name).
- Options window, plus an entry under Options → AddOns.

## 1.1.0
- Named profiles, account-wide; each character remembers its own.

## 1.0.0
- Stateless action bars 1–8 on Blizzard's action button template with a fixed action page: no paging, no secure snippets.
- Keybinds reuse Blizzard's Action Bar bindings and honour "cast on key down".
