#import "TGWallpaperListController.h"

#import <LegacyComponents/LegacyComponents.h>

#import <LegacyComponents/ActionStage.h>

#import "TGAppDelegate.h"

#import "TGWallpaperListLayout.h"
#import "TGWallpaperItemCell.h"

#import "TGCollectionItemView.h"
#import "TGDisclosureActionCollectionItem.h"

#import "TGWallpaperManager.h"
#import <LegacyComponents/TGWallpaperInfo.h>
#import <LegacyComponents/TGCustomImageWallpaperInfo.h>
#import <LegacyComponents/TGRemoteWallpaperInfo.h>
#import <LegacyComponents/TGColorWallpaperInfo.h>
#import "TGModernRemoteWallpaperListActor.h"

#import "TGLegacyWallpaperController.h"

#import <LegacyComponents/TGOverlayFormsheetWindow.h>
#import <LegacyComponents/TGOverlayFormsheetController.h>

#import <LegacyComponents/TGMediaAssetsController.h>
#import <LegacyComponents/TGLegacyCameraController.h>
#import <LegacyComponents/TGImagePickerController.h>

#import "TGLegacyComponentsContext.h"

#import "TGAppearanceController.h"

#import "TGPresentation.h"
#import "TGDefaultPresentationPallete.h"

@interface TGWallpaperListController () <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, TGLegacyWallpaperControllerDelegate, TGLegacyCameraControllerDelegate, TGImagePickerControllerDelegate>
{
    UICollectionView *_collectionView;
    TGWallpaperListLayout *_collectionLayout;
    NSMutableSet *_collectionRegisteredItemIdentifiers;
    CGFloat _currentLayoutWidth;
    
    NSArray *_wallpaperItems;
    
    TGDisclosureActionCollectionItem *_photoLibraryItem;
    
    __weak TGOverlayFormsheetWindow *_photoLibraryWindow;
}

@end

@implementation TGWallpaperListController

- (id)init
{
    self = [super init];
    if (self != nil)
    {
        _actionHandle = [[ASHandle alloc] initWithDelegate:self releaseOnMainThread:true];
        
        [self setTitleText:TGLocalized(@"Wallpaper.Title")];
        
        _photoLibraryItem = [[TGDisclosureActionCollectionItem alloc] initWithTitle:TGLocalized(@"Wallpaper.PhotoLibrary") action:@selector(photoLibraryPressed)];
        _photoLibraryItem.deselectAutomatically = TGIsPad();
        
        TGPresentation *presentation = TGPresentation.current;
        NSMutableArray *wallpaperItems = [[NSMutableArray alloc] init];
        if (![presentation.pallete isMemberOfClass:[TGDefaultPresentationPallete class]])
            [wallpaperItems addObject:[[TGColorWallpaperInfo alloc] initWithColor:TGColorHexCode(presentation.pallete.backgroundColor)]];
        [wallpaperItems addObjectsFromArray:[[TGWallpaperManager instance] builtinWallpaperList]];
        [wallpaperItems addObjectsFromArray:[TGModernRemoteWallpaperListActor cachedList]];
        _wallpaperItems = wallpaperItems;
        
        [ActionStageInstance() requestActor:@"/tg/remoteWallpapers/(cached)" options:nil flags:0 watcher:self];
    }
    return self;
}

- (void)dealloc
{
    _collectionView.delegate = nil;
    _collectionView.dataSource = nil;
    
    [_actionHandle reset];
    [ActionStageInstance() removeWatcher:self];
}

- (void)setPresentation:(TGPresentation *)presentation
{
    _presentation = presentation;
    _photoLibraryItem.presentation = presentation;
}

- (void)loadView
{
    [super loadView];
    
    self.view.backgroundColor = _presentation.pallete.collectionMenuBackgroundColor;
    
    _currentLayoutWidth = self.view.frame.size.width;
    _collectionRegisteredItemIdentifiers = [[NSMutableSet alloc] init];
    
    _collectionLayout = [[TGWallpaperListLayout alloc] init];
    _collectionLayout.presentation = self.presentation;
    _collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:_collectionLayout];
    if (iosMajorVersion() >= 11)
        _collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collectionView.backgroundColor = nil;
    _collectionView.opaque = false;
    _collectionView.delegate = self;
    _collectionView.dataSource = self;
    _collectionView.alwaysBounceVertical = true;
    [_collectionView registerClass:[TGCollectionItemView class] forCellWithReuseIdentifier:@"_empty"];
    [_collectionView registerClass:[TGWallpaperItemCell class] forCellWithReuseIdentifier:@"_wallpaper"];
    [self.view addSubview:_collectionView];
    
    [self setExplicitTableInset:UIEdgeInsetsMake(-(TGScreenPixel), 0, 0, 0)];
    if (![self _updateControllerInset:false])
        [self controllerInsetUpdated:UIEdgeInsetsZero];
}

#pragma mark -

- (void)viewWillAppear:(BOOL)animated
{
    CGFloat currentLayoutWidth = [TGViewController screenSizeForInterfaceOrientation:self.interfaceOrientation].width;
    if (ABS(currentLayoutWidth - _currentLayoutWidth) > FLT_EPSILON)
    {
        _currentLayoutWidth = currentLayoutWidth;
        [_collectionLayout invalidateLayout];
    }
    
    for (NSIndexPath *indexPath in [_collectionView indexPathsForSelectedItems])
    {
        [_collectionView deselectItemAtIndexPath:indexPath animated:animated];
    }
    
    [super viewWillAppear:animated];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    _currentLayoutWidth = [TGViewController screenSizeForInterfaceOrientation:toInterfaceOrientation].width;
    [_collectionLayout invalidateLayout];
    
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
}

- (void)controllerInsetUpdated:(UIEdgeInsets)previousInset
{
    [super controllerInsetUpdated:previousInset];
    
    if ([self isViewLoaded]) {
        for (TGCollectionItemView *itemView in [_collectionView visibleCells])
        {
            if (![itemView isKindOfClass:[TGCollectionItemView class]])
                continue;
            
            itemView.safeAreaInset = self.controllerSafeAreaInset;
        }
    }
}

#pragma mark -

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)__unused collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0)
        return CGSizeMake(collectionView.frame.size.width, 44.0f);
    else
    {
        if (TGIsPad())
        {
            CGSize layoutSize = collectionView.frame.size;
            if ([self inPopover])
                layoutSize.width = 320.0f;
            else if ([self inFormSheet])
                layoutSize.width = 540.0f;
            
            if (layoutSize.width > 320.0f + FLT_EPSILON)
                return CGSizeMake(110.0f, 146.0f);
            else
                return CGSizeMake(91.0f, 121.0f);
        }
        else
        {
            CGSize screenSize = TGScreenSize();
            CGFloat widescreenWidth = MAX(screenSize.width, screenSize.height);
            
            if ([UIScreen mainScreen].scale >= 2.0f - FLT_EPSILON)
            {
                if (widescreenWidth >= 812.0f - FLT_EPSILON)
                {
                    return CGSizeMake(108.0f, 163.0f);
                }
                else if (widescreenWidth >= 736.0f - FLT_EPSILON)
                {
                    return CGSizeMake(122.0f, 216.0f);
                }
                else if (widescreenWidth >= 667.0f - FLT_EPSILON)
                {
                    return CGSizeMake(108.0f, 163.0f);
                }
                else
                {
                    return CGSizeMake(91.0f, 162.0f);
                }
            }
            else
            {
                return CGSizeMake(91.0f, 162.0f);
            }
        }
        
        return CGSizeMake(91.0f, 162.0f);
    }
}

- (UIEdgeInsets)collectionView:(UICollectionView *)__unused collectionView layout:(UICollectionViewLayout *)__unused collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    if (section == 0)
        return UIEdgeInsetsMake(32.0f, 0.0f, 0.0f, 0.0f);
    
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait;
    if (collectionView.frame.size.width > collectionView.frame.size.height)
        orientation = UIInterfaceOrientationLandscapeLeft;
    
    UIEdgeInsets safeAreaInset = [self calculatedSafeAreaInset];
    return UIEdgeInsetsMake(32.0f + 15.0f, 15.0f + safeAreaInset.left, 15.0f + 32.0f, 15.0f + safeAreaInset.left);
}

- (CGFloat)collectionView:(UICollectionView *)__unused collectionView layout:(UICollectionViewLayout *)__unused collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    if (section == 0)
        return 0.0f;
    
    if (TGIsPad())
    {
        CGSize layoutSize = collectionView.frame.size;
        if ([self inPopover])
            layoutSize.width = 320.0f;
        else if ([self inFormSheet])
            layoutSize.width = 540.0f;
        
        if (layoutSize.width > 320.0f + FLT_EPSILON)
            return 14.0f;
        else
            return 8.0f;
    }
    
    return 8.0f;
}

- (CGFloat)collectionView:(UICollectionView *)__unused collectionView layout:(UICollectionViewLayout*)__unused collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    if (section == 0)
        return 0.0f;
    
    return 8.0f;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)__unused collectionView
{
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)__unused collectionView numberOfItemsInSection:(NSInteger)section
{
    if (section == 0)
        return 1;
    
    return _wallpaperItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0)
    {
        TGCollectionItemView *itemView = [_photoLibraryItem dequeueItemView:collectionView registeredIdentifiers:_collectionRegisteredItemIdentifiers forIndexPath:indexPath];
        [itemView setItemPosition:TGCollectionItemViewPositionFirstInBlock | TGCollectionItemViewPositionLastInBlock];
        itemView.safeAreaInset = self.controllerSafeAreaInset;
        [_photoLibraryItem bindView:itemView];
        
        return itemView;
    }
    else if (indexPath.item < (NSInteger)_wallpaperItems.count)
    {
        TGWallpaperItemCell *wallpaperCell = (TGWallpaperItemCell *)[collectionView dequeueReusableCellWithReuseIdentifier:@"_wallpaper" forIndexPath:indexPath];
        wallpaperCell.presentation = self.presentation;
        TGWallpaperInfo *wallpaperInfo = _wallpaperItems[indexPath.item];
        [wallpaperCell setWallpaperInfo:wallpaperInfo];
        [wallpaperCell setIsSelected:[wallpaperInfo isEqual:[[TGWallpaperManager instance] currentWallpaperInfo]]];
        
        return wallpaperCell;
    }
    
    return [collectionView dequeueReusableCellWithReuseIdentifier:@"_empty" forIndexPath:indexPath];
}

#pragma mark -

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0)
    {
        TGCollectionItem *item = _photoLibraryItem;
        
        if (item != nil)
        {
            if (item.deselectAutomatically)
                [collectionView deselectItemAtIndexPath:indexPath animated:true];
            
            [item itemSelected:self];
        }
    }
    else
    {
        TGWallpaperItemCell *wallpaperCell = (TGWallpaperItemCell *)[collectionView cellForItemAtIndexPath:indexPath];
        UIImage *currentImage = [wallpaperCell currentImage];
        if (currentImage)
        {
            TGLegacyWallpaperController *wallpaperController = [[TGLegacyWallpaperController alloc] initWithWallpaperInfo:_wallpaperItems[indexPath.item] thumbnailImage:currentImage];
            wallpaperController.delegate = self;
            wallpaperController.presentation = self.presentation;
            
            if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
                wallpaperController.modalPresentationStyle = UIModalPresentationFormSheet;
            
            [TGAppDelegateInstance.rootController presentViewController:wallpaperController animated:true completion:nil];
        }
    }
}

- (void)wallpaperController:(TGLegacyWallpaperController *)__unused wallpaperController didSelectWallpaperWithInfo:(TGWallpaperInfo *)wallpaperInfo
{
    if (wallpaperInfo != nil)
    {
        bool shouldReset = [TGPresentationPallete hasWallpaper] == [wallpaperInfo isKindOfClass:[TGColorWallpaperInfo class]];
        [[TGWallpaperManager instance] setCurrentWallpaperWithInfo:wallpaperInfo];
        if (shouldReset)
            [self.presentation.images resetBubbleBackgrounds];
        
        for (id cell in [_collectionView visibleCells])
        {
            if ([cell isKindOfClass:[TGWallpaperItemCell class]])
            {
                [(TGWallpaperItemCell *)cell setIsSelected:[((TGWallpaperItemCell *)cell).wallpaperInfo isEqual:[[TGWallpaperManager instance] currentWallpaperInfo]]];
            }
        }
        
        [self _dismissPhotoLibrary];
    }
    
    for (TGViewController *controller in self.navigationController.viewControllers)
    {
        if ([controller isKindOfClass:[TGAppearanceController class]])
        {
            [self.navigationController popToViewController:controller animated:false];
            break;
        }
    }
}

- (void)photoLibraryPressed
{
    TGLegacyCameraController *imagePickerController = [[TGLegacyCameraController alloc] initWithContext:[TGLegacyComponentsContext shared]];
    imagePickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    imagePickerController.completionDelegate = self;
    
    [self presentViewController:imagePickerController animated:true completion:nil];
}

- (void)_dismissPhotoLibrary
{
    TGOverlayFormsheetWindow *photoLibraryWindow = _photoLibraryWindow;
    if (photoLibraryWindow != nil)
        [photoLibraryWindow dismissAnimated:true];
    else
        [self dismissViewControllerAnimated:true completion:nil];
}

- (void)legacyCameraControllerCompletedWithNoResult
{
    [self _dismissPhotoLibrary];
}

- (void)imagePickerController:(TGImagePickerController *)__unused imagePicker didFinishPickingWithAssets:(NSArray *)assets
{
    TGOverlayFormsheetWindow *photoLibraryWindow = _photoLibraryWindow;
    UINavigationController *controller = (UINavigationController *)((photoLibraryWindow != nil) ? [(TGOverlayFormsheetController *)[photoLibraryWindow rootViewController] viewController] : self.presentedViewController);
    
    if ([controller isKindOfClass:[UINavigationController class]] && assets.count != 0 && [assets[0] isKindOfClass:[UIImage class]])
    {
        UIImage *wallpaperImage = assets[0];
        
        TGLegacyWallpaperController *wallpaperController = [[TGLegacyWallpaperController alloc] initWithWallpaperInfo:[[TGCustomImageWallpaperInfo alloc] initWithImage:wallpaperImage] thumbnailImage:nil];
        wallpaperController.presentation = self.presentation;
        wallpaperController.delegate = self;
        wallpaperController.enableWallpaperAdjustment = true;
        wallpaperController.doNotFlipIfRTL = true;
        [controller pushViewController:wallpaperController animated:true];
    }
    else
    {
        [self _dismissPhotoLibrary];
    }
}

#pragma mark -

- (void)actorCompleted:(int)status path:(NSString *)path result:(id)result
{
    if ([path hasPrefix:@"/tg/remoteWallpapers/"])
    {
        if (status == ASStatusSuccess)
        {
            NSArray *wallpaperInfos = result[@"wallpaperInfos"];
            
            TGDispatchOnMainThread(^
            {
                NSMutableArray *wallpaperItems = [[NSMutableArray alloc] init];
                
                for (TGWallpaperInfo *wallpaperInfo in _wallpaperItems)
                {
                    if (![wallpaperInfo isKindOfClass:[TGRemoteWallpaperInfo class]])
                        [wallpaperItems addObject:wallpaperInfo];
                }
                
                [wallpaperItems addObjectsFromArray:wallpaperInfos];
                
                bool changed = false;
                
                if (wallpaperItems.count != _wallpaperItems.count)
                    changed = true;
                else
                {
                    for (int i = 0; i < (int)_wallpaperItems.count; i++)
                    {
                        if (![_wallpaperItems[i] isEqual:wallpaperItems[i]])
                        {
                            changed = true;
                            break;
                        }
                    }
                }
                
                if (changed)
                {
                    _wallpaperItems = wallpaperItems;
                    [_collectionView reloadData];
                }
            });
        }
    }
}

@end
