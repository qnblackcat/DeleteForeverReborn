// iOS 17–26: PXPhotoKitDeletePhotosActionController (PhotosUICore).
// iOS 17 refuses to expunge assets that are not trashed, so the regular delete runs first,
// then PXExpungeAssetsAction expunges the same assets.
//
// iOS 18+ differences (checked against 18.2 22C152 and 26.1 23B85):
//   - _handleMainAlertConfirmed:(BOOL) became _handleMainAlertConfirmation:(int64_t), 1 = confirm.
//   - PXExpungeAssetsAction is a PXDestructiveAssetsAction: -initWithAssets: abort()s,
//     -initWithAssets:record: with a PXActionRecord must be used instead.
//   - iOS 26 only lists PXActionRecord's 4-argument initializer (with `variant:`).

#import "Shared.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>

// Takes only the success flag (see -_handleFinalUserDecisionShouldDelete: / -_handleFinalConfirmation:).
typedef void (^DFRDestructiveCompletion)(BOOL success);

@interface DFRDeletePhotosActionController (iOS17)
@property (nonatomic, readonly) NSUndoManager *undoManager;
- (NSArray<PHAsset *> *)_assets;
- (void)_runDestructiveActionWithCompletion:(DFRDestructiveCompletion)completion;
- (void)_handleMainAlertConfirmation:(NSInteger)confirmation; // iOS 18: 1 = confirm, 2 = cancel
@end

// The same action Photos runs for "Delete" inside Recently Deleted.
@interface PXExpungeAssetsAction : NSObject
- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets;                   // iOS 17
- (instancetype)initWithAssets:(NSArray<PHAsset *> *)assets record:(id)record; // iOS 18
- (void)executeWithUndoManager:(NSUndoManager *)undoManager completionHandler:(void (^)(BOOL success))completionHandler;
@end

// iOS 18+. A destructive action whose record says "confirmed" must cover exactly `assetCount` assets.
@interface PXActionRecord : NSObject
- (instancetype)initWithSourceIdentifier:(NSString *)sourceIdentifier variant:(NSString *)variant assetCount:(NSInteger)assetCount userConfirmation:(NSInteger)userConfirmation; // iOS 18, 26
- (instancetype)initWithSourceIdentifier:(NSString *)sourceIdentifier assetCount:(NSInteger)assetCount userConfirmation:(NSInteger)userConfirmation;                              // iOS 18
@end

@interface PHFetchOptions (DFRPrivate)
- (void)setIncludeTrashedAssets:(BOOL)include;
- (void)setPhotoLibrary:(PHPhotoLibrary *)photoLibrary;
@end

@interface PHObject (DFRPrivate)
- (PHPhotoLibrary *)photoLibrary;
@end

@interface PHPhotoLibrary (DFRPrivate)
- (PHFetchOptions *)librarySpecificFetchOptions;
@end

static const NSInteger kDFRUserConfirmationConfirmed = 1;
static const void *kDFRExpungeAfterDeleteKey = &kDFRExpungeAfterDeleteKey;

// Photos.app manages several libraries, so +[PHPhotoLibrary sharedPhotoLibrary] throws there;
// fetch options must name the asset's own library.
static PHFetchOptions *DFRFetchOptionsForAsset(PHAsset *asset) {
	PHPhotoLibrary *library = [asset respondsToSelector:@selector(photoLibrary)] ? [asset photoLibrary] : nil;
	if (!library) return nil;
	if ([library respondsToSelector:@selector(librarySpecificFetchOptions)]) return [library librarySpecificFetchOptions];
	PHFetchOptions *options = [PHFetchOptions new];
	if (![options respondsToSelector:@selector(setPhotoLibrary:)]) return nil;
	options.photoLibrary = library;
	return options;
}

// Re-fetch so the expunge sees the assets in their trashed state, not the pre-delete snapshot.
static NSArray<PHAsset *> *DFRRefetchTrashedAssets(NSArray<PHAsset *> *assets) {
	PHFetchOptions *options = DFRFetchOptionsForAsset(assets.firstObject);
	if (!options) return assets;
	if ([options respondsToSelector:@selector(setIncludeTrashedAssets:)]) options.includeTrashedAssets = YES;

	NSMutableArray<PHAsset *> *fresh = [NSMutableArray arrayWithCapacity:assets.count];
	@try {
		NSArray<NSString *> *identifiers = [assets valueForKey:@"localIdentifier"];
		PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:identifiers options:options];
		[result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) { [fresh addObject:asset]; }];
	} @catch (NSException *exception) {
		return assets;
	}
	return fresh.count ? fresh : assets;
}

static PXActionRecord *DFRMakeConfirmedRecord(NSUInteger assetCount) {
	static NSString *const source = @"PXPhotoKitDeletePhotosActionController";
	Class recordClass = objc_getClass("PXActionRecord");
	if ([recordClass instancesRespondToSelector:@selector(initWithSourceIdentifier:variant:assetCount:userConfirmation:)]) {
		return [[recordClass alloc] initWithSourceIdentifier:source variant:nil assetCount:assetCount userConfirmation:kDFRUserConfirmationConfirmed];
	}
	if ([recordClass instancesRespondToSelector:@selector(initWithSourceIdentifier:assetCount:userConfirmation:)]) {
		return [[recordClass alloc] initWithSourceIdentifier:source assetCount:assetCount userConfirmation:kDFRUserConfirmationConfirmed];
	}
	return nil;
}

static PXExpungeAssetsAction *DFRMakeExpungeAction(NSArray<PHAsset *> *assets) {
	Class actionClass = objc_getClass("PXExpungeAssetsAction");
	// iOS 18: -initWithAssets: still exists but abort()s, so never fall back to it there.
	if ([actionClass instancesRespondToSelector:@selector(initWithAssets:record:)]) {
		PXActionRecord *record = DFRMakeConfirmedRecord(assets.count);
		return record ? [[actionClass alloc] initWithAssets:assets record:record] : nil;
	}
	if ([actionClass instancesRespondToSelector:@selector(initWithAssets:)]) return [[actionClass alloc] initWithAssets:assets];
	return nil;
}

// On any failure the assets stay in Recently Deleted; better than taking Photos down.
static void DFRExpungeAssets(NSArray<PHAsset *> *assets, NSUndoManager *undoManager, void (^completion)(void)) {
	PXExpungeAssetsAction *action = nil;
	@try {
		if (assets.count) action = DFRMakeExpungeAction(DFRRefetchTrashedAssets(assets));
		[action executeWithUndoManager:undoManager completionHandler:^(BOOL success) {
			dispatch_async(dispatch_get_main_queue(), completion);
		}];
	} @catch (NSException *exception) {
		action = nil;
	}
	if (!action) completion();
}

%group PX
%hook PXPhotoKitDeletePhotosActionController
- (void)_setMainAlertController:(UIAlertController *)alert {
	%orig;
	DFRAddPermanentDeleteAction((DFRDeletePhotosActionController *)self, alert, ^(DFRDeletePhotosActionController *controller) {
		// Let the regular delete run; _runDestructiveActionWithCompletion: expunges afterwards.
		objc_setAssociatedObject(controller, kDFRExpungeAfterDeleteKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if ([controller respondsToSelector:@selector(_handleMainAlertConfirmation:)]) {
			[controller _handleMainAlertConfirmation:kDFRUserConfirmationConfirmed];
		} else {
			[controller _handleMainAlertConfirmed:YES];
		}
	});
}

- (void)_runDestructiveActionWithCompletion:(DFRDestructiveCompletion)completion {
	DFRDeletePhotosActionController *controller = (DFRDeletePhotosActionController *)self;
	if (![objc_getAssociatedObject(self, kDFRExpungeAfterDeleteKey) boolValue] || controller.action > 1) {
		%orig;
		return;
	}
	objc_setAssociatedObject(self, kDFRExpungeAfterDeleteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	// Step 1: move to Recently Deleted. Step 2: expunge the same (now trashed) assets.
	// The caller's completion runs once, after the expunge.
	NSArray<PHAsset *> *assets = [controller _assets];
	NSUndoManager *undoManager = [controller undoManager];
	DFRDestructiveCompletion originalCompletion = [completion copy];
	// The success flag iOS 17 passes here is not reliable (the register held a selector in a
	// crash log), so ignore the block's arguments.
	void (^expungeAfterDelete)(void) = ^{
		dispatch_async(dispatch_get_main_queue(), ^{
			DFRExpungeAssets(assets, undoManager, ^{
				if (originalCompletion) originalCompletion(YES);
			});
		});
	};
	%orig((DFRDestructiveCompletion)expungeAfterDelete);
}
%end
%end

static void DFRInstall(Class cls) {
	%init(PX, PXPhotoKitDeletePhotosActionController = cls);
}

%ctor {
	if (@available(iOS 17.0, *)) DFRHookClassWhenLoaded("PXPhotoKitDeletePhotosActionController", DFRInstall);
}
