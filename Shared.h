// DeleteForeverReborn — rebuilt from DeleteForeverXS 1.1 (original by P2KDev), iOS 15–26.
//
// Adds a "Permanently Delete" button to the Photos delete confirmation sheet that
// skips "Recently Deleted".
//
//   iOS15_16.x: PUDeletePhotosActionController (PhotosUI / PhotosUIPrivate).
//   iOS17.x   : PXPhotoKitDeletePhotosActionController (PhotosUICore), iOS 17–26.
//   Shared.m  : the button and hook installation both versions use.

#import <UIKit/UIKit.h>

// Common interface of PUDeletePhotosActionController and PXPhotoKitDeletePhotosActionController.
@interface DFRDeletePhotosActionController : NSObject
@property (nonatomic, readonly) long long action;
- (void)_handleMainAlertConfirmed:(BOOL)confirmed; // iOS 15–17
@end

// Adds the "Permanently …" button below the regular delete button of a delete sheet.
// When tapped, `confirm` must set up the permanent delete and confirm the sheet.
void DFRAddPermanentDeleteAction(DFRDeletePhotosActionController *controller, UIAlertController *alert,
                                 void (^confirm)(DFRDeletePhotosActionController *controller));

// Calls `install` with the class once it exists. Camera loads PhotosUICore / PhotosUIPrivate
// only when the photo review opens, so a missing class is retried as those frameworks load.
// Called once per process.
void DFRHookClassWhenLoaded(const char *className, void (*install)(Class cls));
