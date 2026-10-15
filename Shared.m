#import "Shared.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

@interface UIAlertController (DFRPrivate)
- (NSMutableArray *)_actions;
@end

static const void *kDFRAddedKey = &kDFRAddedKey;

static NSString *DFRPermanentTitle(NSString *deleteTitle) {
	NSString *lang = NSLocale.preferredLanguages.firstObject ?: @"";
	if ([lang hasPrefix:@"vi"]) return [NSString stringWithFormat:@"%@ vĩnh viễn", deleteTitle];
	return [NSString stringWithFormat:@"Permanently %@", deleteTitle];
}

void DFRAddPermanentDeleteAction(DFRDeletePhotosActionController *controller, UIAlertController *alert,
                                 void (^confirm)(DFRDeletePhotosActionController *controller)) {
	if (!alert || objc_getAssociatedObject(alert, kDFRAddedKey)) return;

	// 0/1 are the regular "move to Recently Deleted" actions; leave restore/hide/expunge sheets alone.
	long long action = [controller action];
	if (action != 0 && action != 1) return;

	// iOS 17+ puts the delete button first, older versions after Cancel, so find it by style.
	UIAlertAction *deleteAction = nil;
	for (UIAlertAction *a in alert.actions) {
		if (a.style == UIAlertActionStyleDestructive) { deleteAction = a; break; }
	}
	if (!deleteAction) {
		for (UIAlertAction *a in alert.actions) {
			if (a.style != UIAlertActionStyleCancel) { deleteAction = a; break; }
		}
	}
	if (!deleteAction.title) return;

	__weak DFRDeletePhotosActionController *weakController = controller;
	UIAlertAction *permanentAction = [UIAlertAction actionWithTitle:DFRPermanentTitle(deleteAction.title)
	                                                          style:UIAlertActionStyleDestructive
	                                                        handler:^(UIAlertAction *a) {
		DFRDeletePhotosActionController *strongController = weakController;
		if (strongController) confirm(strongController);
	}];
	[alert addAction:permanentAction];
	objc_setAssociatedObject(alert, kDFRAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	// Place it right below the regular delete button.
	if ([alert respondsToSelector:@selector(_actions)]) {
		id actions = [alert _actions];
		if ([actions isKindOfClass:[NSMutableArray class]]) {
			NSUInteger deleteIndex = [actions indexOfObjectIdenticalTo:deleteAction];
			NSUInteger permanentIndex = [actions indexOfObjectIdenticalTo:permanentAction];
			if (deleteIndex != NSNotFound && permanentIndex != NSNotFound && permanentIndex != deleteIndex + 1) {
				[actions removeObjectAtIndex:permanentIndex];
				if (permanentIndex < deleteIndex) deleteIndex--;
				[actions insertObject:permanentAction atIndex:deleteIndex + 1];
			}
		}
	}
}

static const char *sDFRClassName;
static void (*sDFRInstall)(Class cls);
static BOOL sDFRInstalled;

static void DFRInstallIfLoaded(void) {
	if (sDFRInstalled) return;
	Class cls = objc_getClass(sDFRClassName);
	if (!cls) return;
	sDFRInstalled = YES;
	sDFRInstall(cls);
}

static void DFRImageAdded(const struct mach_header *header, intptr_t slide) {
	if (sDFRInstalled) return;
	Dl_info info;
	if (!dladdr(header, &info) || !info.dli_fname) return;
	if (!strstr(info.dli_fname, "/PhotosUICore.framework/") && !strstr(info.dli_fname, "/PhotosUIPrivate.framework/")) return;
	// Classes are registered once the load finishes; nothing can show a delete sheet before that.
	dispatch_async(dispatch_get_main_queue(), ^{ DFRInstallIfLoaded(); });
}

void DFRHookClassWhenLoaded(const char *className, void (*install)(Class cls)) {
	sDFRClassName = className;
	sDFRInstall = install;
	DFRInstallIfLoaded();
	if (!sDFRInstalled) _dyld_register_func_for_add_image(DFRImageAdded);
}
