A half-height sheet that confirms one consequential action, such as an install, a reset, or a send that can't be undone.

**Consumer provides:** a question title (`title3`) that names the action and its object, one sentence of consequence, optional `caption` metadata with tabular digits, a confirm verb, and a cancel verb.

**Build with:** `UISheetPresentationController` with the `.medium` detent and the grabber visible. It follows the system appearance, so remove the `overrideUserInterfaceStyle` in `TIOConfirm.m`.

**Rules**
- The confirm verb repeats the title's verb ("Install"), never "OK" or "Yes".
- Cancel is the plain `accent` button below it. Swiping down also cancels.
- Use it for one decision only. Use the OTA wizard for multi-step flows.
