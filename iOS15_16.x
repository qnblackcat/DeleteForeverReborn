// iOS 15–16: PUDeletePhotosActionController (PhotosUI / PhotosUIPrivate).
// Switching the controller's action to expunge (4) before confirming deletes the assets
// without moving them to Recently Deleted.

#import "Shared.h"
#import <objc/runtime.h>

static const long long kDFRExpungeAction = 4;

// The controller's `_action` ivar, or NULL if it is missing or not a long long.
static long long *DFRActionIvarPointer(id controller) {
	Ivar ivar = class_getInstanceVariable(object_getClass(controller), "_action");
	const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
	if (!type || (strcmp(type, "q") != 0 && strcmp(type, "l") != 0)) return NULL;
	return (long long *)((uint8_t *)(__bridge void *)controller + ivar_getOffset(ivar));
}

%group PU
%hook PUDeletePhotosActionController
- (void)_setMainAlertController:(UIAlertController *)alert {
	%orig;
	if (!DFRActionIvarPointer(self)) return;
	DFRAddPermanentDeleteAction((DFRDeletePhotosActionController *)self, alert, ^(DFRDeletePhotosActionController *controller) {
		*DFRActionIvarPointer(controller) = kDFRExpungeAction;
		[controller _handleMainAlertConfirmed:YES];
	});
}
%end
%end

static void DFRInstall(Class cls) {
	%init(PU, PUDeletePhotosActionController = cls);
}

%ctor {
	if (@available(iOS 17.0, *)) return;
	DFRHookClassWhenLoaded("PUDeletePhotosActionController", DFRInstall);
}
