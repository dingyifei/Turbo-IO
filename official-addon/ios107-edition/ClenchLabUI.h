#import <UIKit/UIKit.h>
#if TIO_IMAGE_RX_LAB
// Debug-only Clench Lab page (CLENCH-A). Passive LifeLog capture; see ClenchLab.h.
UIViewController *TIOClenchLabController(void);
// Called once at add-on setup: restores a dump config the Lab left on (crash or kill mid-session). No glasses command.
void TIOClenchLabInstallRecovery(void);
#endif
