//
//  WMPageController.m
//  WMPageController
//
//  Created by Mark on 15/6/11.
//  Copyright (c) 2015年 yq. All rights reserved.
//

#import "WMPageController.h"

NSString *const WMControllerDidAddToSuperViewNotification = @"WMControllerDidAddToSuperViewNotification";
NSString *const WMControllerDidFullyDisplayedNotification = @"WMControllerDidFullyDisplayedNotification";

static NSInteger const kWMUndefinedIndex = -1;
static NSInteger const kWMControllerCountUndefined = -1;
@interface WMPageController () {
    CGFloat _targetX;
    CGRect  _contentViewFrame, _menuViewFrame;
    BOOL    _hasInited, _shouldNotScroll;
    NSInteger _initializedIndex, _controllerCount, _markedSelectIndex;
}
//@property (nonatomic, strong, readwrite) UIViewController *currentViewController;
// 用于记录子控制器view的frame，用于 scrollView 上的展示的位置
//@property (nonatomic, strong) NSMutableArray *childViewFrames;
// 当前展示在屏幕上的控制器，方便在滚动的时候读取 (避免不必要计算)
//@property (nonatomic, strong) NSMutableDictionary *displayVC;
// 用于记录销毁的viewController的位置 (如果它是某一种scrollView的Controller的话)
@property (nonatomic, strong) NSMutableDictionary *posRecords;
// 用于缓存加载过的控制器
//@property (nonatomic, strong) NSCache *memCache;
@property (nonatomic, strong) NSMutableDictionary *backgroundCache;
// 收到内存警告的次数
@property (nonatomic, assign) int memoryWarningCount;
//@property (nonatomic, readonly) NSInteger childControllersCount;
@end

@implementation WMPageController

#pragma mark - ================== 带缓存reload需要考虑的 end ==================
// 重选频道后，当前显示的频道不再，移除当前子控制器，且从display中移除
- (void)zy_removeViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    // 这个废弃方法不用管
    [self wm_rememberPositionIfNeeded:viewController atIndex:index];
    // 子控制器视图移除
    [viewController.view removeFromSuperview];
    [viewController willMoveToParentViewController:nil];
    // 子控制器移除
    [viewController removeFromParentViewController];
    // 当前展示控制器可变字典 中移除
    [self.displayVC removeObjectForKey:@(index)];
}

/*
 重选后，各项准备工作做好了，开始reload。
 这个方法，按照自己以前做这个类型功能的经验，把初始化、点击菜单栏、scrollView点击相关的代码逐行看过。
 把涉及的需要照顾到的属性，都准备好。
 主要也是参照 初始化、点击菜单栏、scrollView点击三个相关功能，揉在一起的方法，写成有运气的成分，也有努力的成分。
 应该有比较多可以优化的地方，不过对代码的其他地方不是很熟，甚至还有一些自己不知道的bug待测试。
 */
- (void)zy_reloadDataWithCacheWithShouldSelect:(NSInteger)shouldSelect{
    
    _controllerCount = kWMControllerCountUndefined;// 触发去取最新的titleCount，更新childControllersCount，
    _hasInited = NO;
    
    
    if (!self.childControllersCount) return;
    
    
    // 强制布局子视图
    
    
    // 计算menuView整个的frame，及子控制器的视图frame，viewDidLoad调用过
    [self wm_calculateSize];
    //    // 重置滚动容器的frame、contentSize
    [self wm_adjustScrollViewFrame];
    
    // menu的title有变化，直接调用了这个，目前没有问题
    [self wm_resetMenuView];
    //    // 重置 菜单视图的frame和其子控件的frame
    [self wm_adjustMenuViewFrame];
    
    // 上一句执行完毕，设置是否初始化完毕标识为 yes
    _hasInited = YES;
    
    // 应当选择索引不是之前那个，那么这里就应该 处理上面的菜单栏的选择、和下面子控制器页面的处理，注意之前处理了- (void)zy_removeViewController:(UIViewController *)viewController atIndex:(NSInteger)index
    
    if (_selectIndex != shouldSelect){
        
        // 没有初始化完，啥也不干
        if (!_hasInited) return;
        // 更新当前选中的索引
        _selectIndex = (int)shouldSelect;
        // 设置，是否是 滚动视图自主滚动为NO
        _startDragging = NO;
        // 计算偏移值
        CGPoint targetP = CGPointMake(_contentViewFrame.size.width * _selectIndex, 0);
        // 设置滚动视图偏移值，点击的 MenuItem 是否触发滚动动画
        [self.scrollView setContentOffset:targetP animated:self.pageAnimatable];
        
        // 更新菜单选中
        [self.menuView slideMenuAtProgress:_selectIndex];
        [self.menuView deselectedItemsIfNeeded];
        
        // 布局子控制器
        [self wm_layoutChildViewControllers];
        // 更新当前显示的控制器
        self.currentViewController = self.displayVC[@(self.selectIndex)];
        // 发出通知
        [self didEnterController:self.currentViewController atIndex:_selectIndex];
        // menu的title有变化，直接调用了这个，目前没有问题
        [self wm_resetMenuView];
        
    }
    
    
    
}

#pragma mark - ================== 带缓存reload需要考虑的 end ==================

#pragma mark - Lazy Loading
- (NSMutableDictionary *)posRecords {
    if (_posRecords == nil) {
        _posRecords = [[NSMutableDictionary alloc] init];
    }
    return _posRecords;
}

- (NSMutableDictionary *)displayVC {
    if (_displayVC == nil) {
        _displayVC = [[NSMutableDictionary alloc] init];
    }
    return _displayVC;
}

- (NSMutableDictionary *)backgroundCache {
    if (_backgroundCache == nil) {
        _backgroundCache = [[NSMutableDictionary alloc] init];
    }
    return _backgroundCache;
}

#pragma mark - Public Methods
- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self wm_setup];
    }
    return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self wm_setup];
    }
    return self;
}

- (instancetype)initWithViewControllerClasses:(NSArray<Class> *)classes andTheirTitles:(NSArray<NSString *> *)titles {
    if (self = [self initWithNibName:nil bundle:nil]) {
        NSParameterAssert(classes.count == titles.count);
        _viewControllerClasses = [NSArray arrayWithArray:classes];
        _titles = [NSArray arrayWithArray:titles];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyToHigh) object:nil];
}

- (void)forceLayoutSubviews {
    if (!self.childControllersCount) return;
    // 计算menuView整个的frame，及子控制器的视图frame，viewDidLoad调用过
    [self wm_calculateSize];
    // 重置滚动容器的frame、contentSize
    [self wm_adjustScrollViewFrame];
    // 重置 菜单视图的frame和其子控件的frame
    [self wm_adjustMenuViewFrame];
    // 遍历正在展示的视图可变字典，取其key（即索引）对应去，子控制器frames数组中取出一开始计算好的frame，重置
    [self wm_adjustDisplayingViewControllersFrame];
}

- (void)setScrollEnable:(BOOL)scrollEnable {
    _scrollEnable = scrollEnable;
    
    if (!self.scrollView) return;
    self.scrollView.scrollEnabled = scrollEnable;
}

- (void)setProgressViewCornerRadius:(CGFloat)progressViewCornerRadius {
    _progressViewCornerRadius = progressViewCornerRadius;
    if (self.menuView) {
        self.menuView.progressViewCornerRadius = progressViewCornerRadius;
    }
}

- (void)setMenuViewLayoutMode:(WMMenuViewLayoutMode)menuViewLayoutMode {
    _menuViewLayoutMode = menuViewLayoutMode;
    if (self.menuView.superview) {
        [self wm_resetMenuView];
    }
}

- (void)setCachePolicy:(WMPageControllerCachePolicy)cachePolicy {
    _cachePolicy = cachePolicy;
    if (cachePolicy != WMPageControllerCachePolicyDisabled) {
        self.memCache.countLimit = _cachePolicy;
    }
}

- (void)setSelectIndex:(int)selectIndex {
    _selectIndex = selectIndex;
    _markedSelectIndex = kWMUndefinedIndex;
    if (self.menuView && _hasInited) {
        [self.menuView selectItemAtIndex:selectIndex];
    } else {
        _markedSelectIndex = selectIndex;
    }
}

- (void)setProgressViewIsNaughty:(BOOL)progressViewIsNaughty {
    _progressViewIsNaughty = progressViewIsNaughty;
    if (self.menuView) {
        self.menuView.progressViewIsNaughty = progressViewIsNaughty;
    }
}

- (void)setProgressWidth:(CGFloat)progressWidth {
    _progressWidth = progressWidth;
    self.progressViewWidths = ({
        NSMutableArray *tmp = [NSMutableArray array];
        for (int i = 0; i < self.childControllersCount; i++) {
            [tmp addObject:@(progressWidth)];
        }
        tmp.copy;
    });
}

- (void)setProgressViewWidths:(NSArray *)progressViewWidths {
    _progressViewWidths = progressViewWidths;
    if (self.menuView) {
        self.menuView.progressWidths = progressViewWidths;
    }
}

- (void)setMenuViewContentMargin:(CGFloat)menuViewContentMargin {
    _menuViewContentMargin = menuViewContentMargin;
    if (self.menuView) {
        self.menuView.contentMargin = menuViewContentMargin;
    }
}

- (void)reloadData {
    [self wm_clearDatas];
    
    if (!self.childControllersCount) return;
    
    [self wm_resetScrollView];
    [self.memCache removeAllObjects];
    [self wm_resetMenuView];
    [self viewDidLayoutSubviews];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}

- (void)updateTitle:(NSString *)title atIndex:(NSInteger)index {
    [self.menuView updateTitle:title atIndex:index andWidth:NO];
}

- (void)updateAttributeTitle:(NSAttributedString * _Nonnull)title atIndex:(NSInteger)index {
    [self.menuView updateAttributeTitle:title atIndex:index andWidth:NO];
}

- (void)updateTitle:(NSString *)title andWidth:(CGFloat)width atIndex:(NSInteger)index {
    if (self.itemsWidths && index < self.itemsWidths.count) {
        NSMutableArray *mutableWidths = [NSMutableArray arrayWithArray:self.itemsWidths];
        mutableWidths[index] = @(width);
        self.itemsWidths = [mutableWidths copy];
    } else {
        NSMutableArray *mutableWidths = [NSMutableArray array];
        for (int i = 0; i < self.childControllersCount; i++) {
            CGFloat itemWidth = (i == index) ? width : self.menuItemWidth;
            [mutableWidths addObject:@(itemWidth)];
        }
        self.itemsWidths = [mutableWidths copy];
    }
    [self.menuView updateTitle:title atIndex:index andWidth:YES];
}

- (void)setShowOnNavigationBar:(BOOL)showOnNavigationBar {
    if (_showOnNavigationBar == showOnNavigationBar) {
        return;
    }
    
    _showOnNavigationBar = showOnNavigationBar;
    if (self.menuView) {
        [self.menuView removeFromSuperview];
        [self wm_addMenuView];
        [self forceLayoutSubviews];
        [self.menuView slideMenuAtProgress:self.selectIndex];
    }
}

#pragma mark - Notification
- (void)willResignActive:(NSNotification *)notification {
    for (int i = 0; i < self.childControllersCount; i++) {
        id obj = [self.memCache objectForKey:@(i)];
        if (obj) {
            [self.backgroundCache setObject:obj forKey:@(i)];
        }
    }
}

- (void)willEnterForeground:(NSNotification *)notification {
    for (NSNumber *key in self.backgroundCache.allKeys) {
        if (![self.memCache objectForKey:key]) {
            [self.memCache setObject:self.backgroundCache[key] forKey:key];
        }
    }
    [self.backgroundCache removeAllObjects];
}

#pragma mark - Delegate
- (NSDictionary *)infoWithIndex:(NSInteger)index {
    NSString *title = [self titleAtIndex:index];
    return @{@"title": title ?: @"", @"index": @(index)};
}

- (void)willCachedController:(UIViewController *)vc atIndex:(NSInteger)index {
    if (self.childControllersCount && [self.delegate respondsToSelector:@selector(pageController:willCachedViewController:withInfo:)]) {
        NSDictionary *info = [self infoWithIndex:index];
        [self.delegate pageController:self willCachedViewController:vc withInfo:info];
    }
}

- (void)willEnterController:(UIViewController *)vc atIndex:(NSInteger)index {
    _selectIndex = (int)index;
    if (self.childControllersCount && [self.delegate respondsToSelector:@selector(pageController:willEnterViewController:withInfo:)]) {
        NSDictionary *info = [self infoWithIndex:index];
        [self.delegate pageController:self willEnterViewController:vc withInfo:info];
    }
}

// 完全进入控制器 (即停止滑动后调用)
- (void)didEnterController:(UIViewController *)vc atIndex:(NSInteger)index {
    if (!self.childControllersCount) return;
    
    // 发送完全展示通知：Post FullyDisplayedNotification
    [self wm_postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
    // 通过代理方法回调这个时间点
    NSDictionary *info = [self infoWithIndex:index];
    if ([self.delegate respondsToSelector:@selector(pageController:didEnterViewController:withInfo:)]) {
        [self.delegate pageController:self didEnterViewController:vc withInfo:info];
    }
    
    // 重量级子控制器第一次初始化的时间点：当控制器创建时，调用延迟加载的代理方法
    if (_initializedIndex == index && [self.delegate respondsToSelector:@selector(pageController:lazyLoadViewController:withInfo:)]) {
        [self.delegate pageController:self lazyLoadViewController:vc withInfo:info];
        _initializedIndex = kWMUndefinedIndex;
    }

    // 根据 preloadPolicy 预加载控制器
    if (self.preloadPolicy == WMPageControllerPreloadPolicyNever) return;
    int length = (int)self.preloadPolicy;
    int start = 0;
    int end = (int)self.childControllersCount - 1;
    if (index > length) {
        start = (int)index - length;
    }
    if (self.childControllersCount - 1 > length + index) {
        end = (int)index + length;
    }
    for (int i = start; i <= end; i++) {
        // 如果已存在，不需要预加载
        if (![self.memCache objectForKey:@(i)] && !self.displayVC[@(i)]) {
            [self wm_addViewControllerAtIndex:i];
            [self wm_postAddToSuperViewNotificationWithIndex:i];
        }
    }
    // 设置选中几号 item
    _selectIndex = (int)index;
}

#pragma mark - Data source
- (NSInteger)childControllersCount {
    if (_controllerCount == kWMControllerCountUndefined) {
        if ([self.dataSource respondsToSelector:@selector(numbersOfChildControllersInPageController:)]) {
            _controllerCount = [self.dataSource numbersOfChildControllersInPageController:self];
        } else {
            _controllerCount = self.viewControllerClasses.count;
        }
    }
    return _controllerCount;
}

- (UIViewController * _Nonnull)initializeViewControllerAtIndex:(NSInteger)index {
    if ([self.dataSource respondsToSelector:@selector(pageController:viewControllerAtIndex:)]) {
        return [self.dataSource pageController:self viewControllerAtIndex:index];
    }
    return [[self.viewControllerClasses[index] alloc] init];
}

- (NSString * _Nonnull)titleAtIndex:(NSInteger)index {
    NSString *title = nil;
    if ([self.dataSource respondsToSelector:@selector(pageController:titleAtIndex:)]) {
        title = [self.dataSource pageController:self titleAtIndex:index];
    } else {
        title = self.titles[index];
    }
    return (title ?: @"");
}

#pragma mark - Private Methods

- (void)wm_resetScrollView {
    if (self.scrollView) {
        [self.scrollView removeFromSuperview];
    }
    [self wm_addScrollView];
    [self wm_addViewControllerAtIndex:self.selectIndex];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
}

- (void)wm_clearDatas {
    _controllerCount = kWMControllerCountUndefined;
    _hasInited = NO;
    NSUInteger maxIndex = (self.childControllersCount - 1 > 0) ? (self.childControllersCount - 1) : 0;
    _selectIndex = self.selectIndex < self.childControllersCount ? self.selectIndex : (int)maxIndex;
    if (self.progressWidth > 0) { self.progressWidth = self.progressWidth; }
    
    NSArray *displayingViewControllers = self.displayVC.allValues;
    for (UIViewController *vc in displayingViewControllers) {
        [vc.view removeFromSuperview];
        [vc willMoveToParentViewController:nil];
        [vc removeFromParentViewController];
    }
    self.memoryWarningCount = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyToHigh) object:nil];
    self.currentViewController = nil;
    [self.posRecords removeAllObjects];
    [self.displayVC removeAllObjects];
}

// 当子控制器init完成时发送通知
- (void)wm_postAddToSuperViewNotificationWithIndex:(int)index {
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":[self titleAtIndex:index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidAddToSuperViewNotification
                                                        object:self
                                                      userInfo:info];
}

// 当子控制器完全展示在user面前时发送通知
- (void)wm_postFullyDisplayedNotificationWithCurrentIndex:(int)index {
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":[self titleAtIndex:index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidFullyDisplayedNotification
                                                        object:self
                                                      userInfo:info];
}

// 初始化一些参数，在init中调用
- (void)wm_setup {
    _titleSizeSelected  = 18.0f;
    _titleSizeNormal    = 15.0f;
    _titleColorSelected = [UIColor colorWithRed:168.0/255.0 green:20.0/255.0 blue:4/255.0 alpha:1];
    _titleColorNormal   = [UIColor colorWithRed:0 green:0 blue:0 alpha:1];
    _menuItemWidth = 65.0f;
    
    _memCache = [[NSCache alloc] init];
    _initializedIndex = kWMUndefinedIndex;
    _markedSelectIndex = kWMUndefinedIndex;
    _controllerCount  = kWMControllerCountUndefined;
    _scrollEnable = YES;
    
    self.automaticallyCalculatesItemWidths = NO;
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.preloadPolicy = WMPageControllerPreloadPolicyNever;
    self.cachePolicy = WMPageControllerCachePolicyNoLimit;
    
    self.delegate = self;
    self.dataSource = self;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}
// lzy:menuView整个的frame，主容器的 frame，两者并被全局变量持有
// 包括宽高，子控制器视图 frame
- (void)wm_calculateSize {
    // lzy170925注：问下代理，有没有设置menuView整个的frame，没有自己算
    if ([self.dataSource respondsToSelector:@selector(pageController:preferredFrameForMenuView:)]) {
        _menuViewFrame = [self.dataSource pageController:self preferredFrameForMenuView:self.menuView];
    } else {
        CGFloat originY = (self.showOnNavigationBar && self.navigationController.navigationBar) ? 0 : CGRectGetMaxY(self.navigationController.navigationBar.frame);
        _menuViewFrame = CGRectMake(0, originY, self.view.frame.size.width, 30.0f);
    }
    // lzy170925注：问下代理，有没有自定义 主容器的frame
    if ([self.dataSource respondsToSelector:@selector(pageController:preferredFrameForContentView:)]) {
        _contentViewFrame = [self.dataSource pageController:self preferredFrameForContentView:self.scrollView];
    } else {
        CGFloat originY = (self.showOnNavigationBar && self.navigationController.navigationBar) ? CGRectGetMaxY(self.navigationController.navigationBar.frame) : CGRectGetMaxY(_menuViewFrame);
        CGFloat tabBarHeight = self.tabBarController.tabBar && !self.tabBarController.tabBar.hidden ? self.tabBarController.tabBar.frame.size.height : 0;
        CGFloat sizeHeight = self.view.frame.size.height - tabBarHeight - originY;
        _contentViewFrame = CGRectMake(0, originY, self.view.frame.size.width, sizeHeight);
    }
    // lzy170925注：有了上一步的，计算所有子页面的frame，并保存在数组中
    _childViewFrames = [NSMutableArray array];
    for (int i = 0; i < self.childControllersCount; i++) {
        CGRect frame = CGRectMake(i * _contentViewFrame.size.width, 0, _contentViewFrame.size.width, _contentViewFrame.size.height);
        [_childViewFrames addObject:[NSValue valueWithCGRect:frame]];
    }
}
// lzy170925注：添加滚动视图容器，并作为属性，且处理手势
- (void)wm_addScrollView {
    WMScrollView *scrollView = [[WMScrollView alloc] init];
    scrollView.scrollsToTop = NO;
    scrollView.pagingEnabled = YES;
    scrollView.backgroundColor = [UIColor whiteColor];
    scrollView.delegate = self;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.bounces = self.bounces;
    scrollView.scrollEnabled = self.scrollEnable;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    
    if (!self.navigationController) return;
    for (UIGestureRecognizer *gestureRecognizer in scrollView.gestureRecognizers) {
        [gestureRecognizer requireGestureRecognizerToFail:self.navigationController.interactivePopGestureRecognizer];
    }
}
// lzy170925注：添加整个人的 菜单视图，被主控制器持有为属性
- (void)wm_addMenuView {
    // 作者自己封装的自定义view
    WMMenuView *menuView = [[WMMenuView alloc] initWithFrame:CGRectZero];
    menuView.delegate = self;
    menuView.dataSource = self;
    menuView.style = self.menuViewStyle;
    menuView.layoutMode = self.menuViewLayoutMode;
    menuView.progressHeight = self.progressHeight;
    menuView.contentMargin = self.menuViewContentMargin;
    menuView.progressViewBottomSpace = self.progressViewBottomSpace;
    menuView.progressWidths = self.progressViewWidths;
    menuView.progressViewIsNaughty = self.progressViewIsNaughty;
    menuView.progressViewCornerRadius = self.progressViewCornerRadius;
    menuView.showOnNavigationBar = self.showOnNavigationBar;
    if (self.titleFontName) {
        menuView.fontName = self.titleFontName;
    }
    if (self.progressColor) {
        menuView.lineColor = self.progressColor;
    }
    if (self.showOnNavigationBar && self.navigationController.navigationBar) {
        self.navigationItem.titleView = menuView;
    } else {
        [self.view addSubview:menuView];
    }
    self.menuView = menuView;
}
/* lzy170925注:
 布局子控制器
 */
- (void)wm_layoutChildViewControllers {
    // lzy:根据滚动容器偏移值，和总容器宽度相除，算出当前索引
    int currentPage = (int)(self.scrollView.contentOffset.x / _contentViewFrame.size.width);
    // lzy:预加载原则
    int length = (int)self.preloadPolicy;
    int left = currentPage - length - 1;
    int right = currentPage + length + 1;
    for (int i = 0; i < self.childControllersCount; i++) {
        UIViewController *vc = [self.displayVC objectForKey:@(i)];
        CGRect frame = [self.childViewFrames[i] CGRectValue];
        if (!vc) {
            if ([self wm_isInScreen:frame]) {
                [self wm_initializedControllerWithIndexIfNeeded:i];
            }
        } else if (i <= left || i >= right) {
            if (![self wm_isInScreen:frame]) {
                [self wm_removeViewController:vc atIndex:i];
            }
        }
    }
}

// 创建或从缓存中获取控制器并添加到视图上
- (void)wm_initializedControllerWithIndexIfNeeded:(NSInteger)index {
    // 先从 cache 中取
    UIViewController *vc = [self.memCache objectForKey:@(index)];
    if (vc) {
        // cache 中存在，添加到 scrollView 上，并放入display
        [self wm_addCachedViewController:vc atIndex:index];
    } else {
        // cache 中也不存在，创建并添加到display
        [self wm_addViewControllerAtIndex:(int)index];
    }
    [self wm_postAddToSuperViewNotificationWithIndex:(int)index];
}

- (void)wm_addCachedViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    [self addChildViewController:viewController];
    viewController.view.frame = [self.childViewFrames[index] CGRectValue];
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self willEnterController:viewController atIndex:index];
    [self.displayVC setObject:viewController forKey:@(index)];
}
// lzy:不存在displayVC和mem，才创建并添加子控制器
// 创建并添加子控制器
- (void)wm_addViewControllerAtIndex:(int)index {
    _initializedIndex = index;
    UIViewController *viewController = [self initializeViewControllerAtIndex:index];
    // lzy170925注：这是页面初始化的时候，kvc给页面赋值的
    if (self.values.count == self.childControllersCount && self.keys.count == self.childControllersCount) {
        [viewController setValue:self.values[index] forKey:self.keys[index]];
    }
    // lzy:添加子控制器
    [self addChildViewController:viewController];
    // lzy:之前计算成功了，那么去以前计算的
    CGRect frame = self.childViewFrames.count ? [self.childViewFrames[index] CGRectValue] : self.view.frame;
    viewController.view.frame = frame;
    // lzy:原生方法
    [viewController didMoveToParentViewController:self];
    // lzy:添加子控制器视图到 滚动容器上
    [self.scrollView addSubview:viewController.view];
    // lzy:通知代理，将进入特定子控制器
    [self willEnterController:viewController atIndex:index];
    // lzy:可变字典，当前展示在屏幕上的控制器，方便在滚动的时候读取 (避免不必要计算)，键是控制器视图所在索引
    [self.displayVC setObject:viewController forKey:@(index)];
    // lzy:这个方法废弃了，默认不记录，什么也不会做
    [self wm_backToPositionIfNeeded:viewController atIndex:index];
}
// lzy:移除控制器，且从display中移除，放入缓存
// 移除控制器，且从display中移除
- (void)wm_removeViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    // lzy:这个废弃方法不用管
    [self wm_rememberPositionIfNeeded:viewController atIndex:index];
    // lzy:子控制器视图移除
    [viewController.view removeFromSuperview];
    [viewController willMoveToParentViewController:nil];
    // lzy:子控制器移除
    [viewController removeFromParentViewController];
    // lzy:当前展示控制器可变字典 中移除
    [self.displayVC removeObjectForKey:@(index)];
    
    // 放入缓存
    if (self.cachePolicy == WMPageControllerCachePolicyDisabled) {
        return;
    }
    
    if (![self.memCache objectForKey:@(index)]) {
        [self willCachedController:viewController atIndex:index];
        [self.memCache setObject:viewController forKey:@(index)];
    }
}

- (void)wm_backToPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index {
#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Wdeprecated-declarations"
    if (!self.rememberLocation) return;
#pragma clang diagnostic pop
    if ([self.memCache objectForKey:@(index)]) return;
    UIScrollView *scrollView = [self wm_isKindOfScrollViewController:controller];
    if (scrollView) {
        NSValue *pointValue = self.posRecords[@(index)];
        if (pointValue) {
            CGPoint pos = [pointValue CGPointValue];
            [scrollView setContentOffset:pos];
        }
    }
}

- (void)wm_rememberPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index {
#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Wdeprecated-declarations"
    if (!self.rememberLocation) return;
#pragma clang diagnostic pop
    UIScrollView *scrollView = [self wm_isKindOfScrollViewController:controller];
    if (scrollView) {
        CGPoint pos = scrollView.contentOffset;
        self.posRecords[@(index)] = [NSValue valueWithCGPoint:pos];
    }
}

- (UIScrollView *)wm_isKindOfScrollViewController:(UIViewController *)controller {
    UIScrollView *scrollView = nil;
    if ([controller.view isKindOfClass:[UIScrollView class]]) {
        // Controller的view是scrollView的子类(UITableViewController/UIViewController替换view为scrollView)
        scrollView = (UIScrollView *)controller.view;
    } else if (controller.view.subviews.count >= 1) {
        // Controller的view的subViews[0]存在且是scrollView的子类，并且frame等与view得frame(UICollectionViewController/UIViewController添加UIScrollView)
        UIView *view = controller.view.subviews[0];
        if ([view isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)view;
        }
    }
    return scrollView;
}

- (BOOL)wm_isInScreen:(CGRect)frame {
    CGFloat x = frame.origin.x;
    CGFloat ScreenWidth = self.scrollView.frame.size.width;
    
    CGFloat contentOffsetX = self.scrollView.contentOffset.x;
    if (CGRectGetMaxX(frame) > contentOffsetX && x - contentOffsetX < ScreenWidth) {
        return YES;
    } else {
        return NO;
    }
}

- (void)wm_resetMenuView {
    if (!self.menuView) {
        [self wm_addMenuView];
    } else {
        [self.menuView reload];
        if (self.menuView.userInteractionEnabled == NO) {
            self.menuView.userInteractionEnabled = YES;
        }
        if (self.selectIndex != 0) {
            [self.menuView selectItemAtIndex:self.selectIndex];
        }
        [self.view bringSubviewToFront:self.menuView];
    }
}

- (void)wm_growCachePolicyAfterMemoryWarning {
    self.cachePolicy = WMPageControllerCachePolicyBalanced;
    [self performSelector:@selector(wm_growCachePolicyToHigh) withObject:nil afterDelay:2.0 inModes:@[NSRunLoopCommonModes]];
}

- (void)wm_growCachePolicyToHigh {
    self.cachePolicy = WMPageControllerCachePolicyHigh;
}

- (UIView *)wm_bottomView {
    return self.tabBarController.tabBar ? self.tabBarController.tabBar : self.navigationController.toolbar;
}

#pragma mark - Adjust Frame
- (void)wm_adjustScrollViewFrame {
    // While rotate at last page, set scroll frame will call `-scrollViewDidScroll:` delegate
    // It's not my expectation, so I use `_shouldNotScroll` to lock it.
    // Wait for a better solution.
    _shouldNotScroll = YES;
    CGFloat oldContentOffsetX = self.scrollView.contentOffset.x;
    CGFloat contentWidth = self.scrollView.contentSize.width;
    self.scrollView.frame = _contentViewFrame;
    self.scrollView.contentSize = CGSizeMake(self.childControllersCount * _contentViewFrame.size.width, 0);
    CGFloat xContentOffset = contentWidth == 0 ? self.selectIndex * _contentViewFrame.size.width : oldContentOffsetX / contentWidth * self.childControllersCount * _contentViewFrame.size.width;
    [self.scrollView setContentOffset:CGPointMake(xContentOffset, 0)];
    _shouldNotScroll = NO;
}

- (void)wm_adjustDisplayingViewControllersFrame {
    [self.displayVC enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, UIViewController * _Nonnull vc, BOOL * _Nonnull stop) {
        NSInteger index = key.integerValue;
        CGRect frame = [self.childViewFrames[index] CGRectValue];
        vc.view.frame = frame;
    }];
}

- (void)wm_adjustMenuViewFrame {
    CGFloat oriWidth = self.menuView.frame.size.width;
    self.menuView.frame = _menuViewFrame;
    [self.menuView resetFrames];
    if (oriWidth != self.menuView.frame.size.width) {
        [self.menuView refreshContenOffset];
    }
}

- (CGFloat)wm_calculateItemWithAtIndex:(NSInteger)index {
    NSString *title = [self titleAtIndex:index];
    UIFont *titleFont = self.titleFontName ? [UIFont fontWithName:self.titleFontName size:self.titleSizeSelected] : [UIFont systemFontOfSize:self.titleSizeSelected];
    NSDictionary *attrs = @{NSFontAttributeName: titleFont};
    CGFloat itemWidth = [title boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading) attributes:attrs context:nil].size.width;
    return ceil(itemWidth);
}

- (void)wm_delaySelectIndexIfNeeded {
    if (_markedSelectIndex != kWMUndefinedIndex) {
        self.selectIndex = (int)_markedSelectIndex;
    }
}

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    if (!self.childControllersCount) return;
    // lzy:算整个menuView的frame，根据子控制器个数，算所有子控制器frame，保存为数组
    [self wm_calculateSize];
    // lzy:添加滚动容器，并处理手势
    [self wm_addScrollView];
    // lzy170925注：初始化，就是添加第0个
    [self wm_addViewControllerAtIndex:self.selectIndex];
    // lzy:当前的控制器，从key为索引的，可变字典中取出的，在上一步添加的时候设置进入可变字典的
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    // lzy:添加menuView，被主控制器持有为属性
    [self wm_addMenuView];
    // lzy:通知这个时间点：完全进入控制器 (即停止滑动后调用)
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}
/* lzy170925注:
 控制器的view执行完 layoutSubviews方法后，将会到达这个时间点
 Called just after the view controller's view's layoutSubviews method is invoked. Subclasses can implement as necessary. The default is a nop.
 */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    if (!self.childControllersCount) return;
    // lzy:强制布局子视图
    [self forceLayoutSubviews];
    // lzy:上一句执行完毕，设置是否初始化完毕标识为 yes
    _hasInited = YES;
    // lzy:菜单视图不存，或者且上一个标识为NO，被选中的标识都暂时放在 _markedSelectIndex，现在可以赋值回去
    [self wm_delaySelectIndexIfNeeded];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    self.memoryWarningCount++;
    self.cachePolicy = WMPageControllerCachePolicyLowMemory;
    // 取消正在增长的 cache 操作
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyToHigh) object:nil];
    
    [self.memCache removeAllObjects];
    [self.posRecords removeAllObjects];
    self.posRecords = nil;
    
    // 如果收到内存警告次数小于 3，一段时间后切换到模式 Balanced
    if (self.memoryWarningCount < 3) {
        [self performSelector:@selector(wm_growCachePolicyAfterMemoryWarning) withObject:nil afterDelay:3.0 inModes:@[NSRunLoopCommonModes]];
    }
}

#pragma mark - UIScrollView Delegate lzy排过序了，依次往下
/* lzy170925注:
 滚动和拖拽的几个方法都是在让 菜单视图和 滚动同步：
 1、启用和禁用 菜单视图的 交互
 2、slideMenuAtProgress
 3、deselectedItemsIfNeeded
 
 
 
 已经开始 滚动
 */
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    if (_shouldNotScroll || !_hasInited) return;
    
    // 布局子控制器
    [self wm_layoutChildViewControllers];
    
    if (_startDragging) {
        CGFloat contentOffsetX = scrollView.contentOffset.x;
        if (contentOffsetX < 0) {
            contentOffsetX = 0;
        }
        if (contentOffsetX > scrollView.contentSize.width - _contentViewFrame.size.width) {
            contentOffsetX = scrollView.contentSize.width - _contentViewFrame.size.width;
        }
        CGFloat rate = contentOffsetX / _contentViewFrame.size.width;
        [self.menuView slideMenuAtProgress:rate];
    }
    
    // Fix scrollView.contentOffset.y -> (-20) unexpectedly.
    if (scrollView.contentOffset.y == 0) return;
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.y = 0.0;
    scrollView.contentOffset = contentOffset;
}
/* lzy170925注:
 将要开始 拖拽
 */
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    _startDragging = YES;
    self.menuView.userInteractionEnabled = NO;
}
/* lzy170925注:
 将要结束 拖拽
 */
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    _targetX = targetContentOffset->x;
}

/* lzy170925注:
 已经结束 拖拽
 */
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    if (!decelerate) {
        self.menuView.userInteractionEnabled = YES;
        CGFloat rate = _targetX / _contentViewFrame.size.width;
        [self.menuView slideMenuAtProgress:rate];
        [self.menuView deselectedItemsIfNeeded];
    }
}


/* lzy170925注:
 结束惯性：
 
 启用菜单交互，
 更新“选中的索引”，
 更新当前的自控制器，
 通知当前显示的控制器显示了，
 菜单视图deselectedItemsIfNeeded
 */
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    self.menuView.userInteractionEnabled = YES;
    _selectIndex = (int)(scrollView.contentOffset.x / _contentViewFrame.size.width);
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
    [self.menuView deselectedItemsIfNeeded];
}
/* lzy170925注:
 滚动动画 结束
 */
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
    [self.menuView deselectedItemsIfNeeded];
}

/* TODO: #待完成#
 菜单选择和滚动容器滚动，需要涉及的变量：
 1、当前选中的索引_selectIndex
 2、self.displayVC，放着索引，对应的子控制器
 3、从self.displayVC移除的时候，会放入self.memCache，也是放着索引和对应的子控制器
 4、都要布局子控制器：
 4.1：self.childControllersCount
 4.2：self.displayVC
 4.3：self.childViewFrames
 5、self.currentViewController
 */

#pragma mark - WMMenuView Delegate
- (BOOL)menuView:(WMMenuView *)menu shouldSelesctedIndex:(NSInteger)index{
    return YES;
}

/* lzy170925注:
 手动点击 菜单栏，会触发的方法。
 
 首先要做下过滤：
 1、_hasInited必须是yes
 2、
 猜测应该处理的事情，点了第几个，去滚动到第几个子view上
 1、计算滚动容器 偏移值
 2、更新正在展示的视图可变字典
 3、更新当前的索引（mark索引）
 
 如果那个索引还没有初始化:
 1、需要初始化控制器
 2、添加子视图
 3、缓存之前展示的控制器memCache
 
 如果初始化过：
 1、看下当前展示的控制器可变字典里有没有，有拿出来展示
 2、没有，看下memCache有没有缓存，有拿出来
 
 */
- (void)menuView:(WMMenuView *)menu didSelesctedIndex:(NSInteger)index currentIndex:(NSInteger)currentIndex {
    if (index == currentIndex) return;
    
    // 没有初始化完，啥也不干
    if (!_hasInited) return;
    // 更新当前选中的索引
    _selectIndex = (int)index;
    // 设置，是否是 滚动视图自主滚动为NO
    _startDragging = NO;
    // 计算偏移值
    CGPoint targetP = CGPointMake(_contentViewFrame.size.width * index, 0);
    // 设置滚动视图偏移值，点击的 MenuItem 是否触发滚动动画
    [self.scrollView setContentOffset:targetP animated:self.pageAnimatable];
    // 如果 触发滚动动画，这个方法导致为止，猜测作者在滚动方法里处理下面的逻辑了
    if (self.pageAnimatable) return;
    
    
    // 由于不触发 -scrollViewDidScroll: 手动处理控制器:
    /* lzy170925注:
     看下当前展示的控制器可变字典里有没有，取出目前索引控制器：
     1、移除子控制器和子控制器view，
     2、且从displayVC可变字典中移除，
     3、放入缓存
     */
    UIViewController *currentViewController = self.displayVC[@(currentIndex)];
    if (currentViewController) {
        [self wm_removeViewController:currentViewController atIndex:currentIndex];
    }
    
    // 布局子控制器
    [self wm_layoutChildViewControllers];
    // 更新当前显示的控制器
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    // 发出通知
    [self didEnterController:self.currentViewController atIndex:index];
    
    
}

- (CGFloat)menuView:(WMMenuView *)menu widthForItemAtIndex:(NSInteger)index {
    if (self.automaticallyCalculatesItemWidths) {
        return [self wm_calculateItemWithAtIndex:index];
    }
    
    if (self.itemsWidths.count == self.childControllersCount) {
        return [self.itemsWidths[index] floatValue];
    }
    return self.menuItemWidth;
}

- (CGFloat)menuView:(WMMenuView *)menu itemMarginAtIndex:(NSInteger)index {
    if (self.itemsMargins.count == self.childControllersCount + 1) {
        return [self.itemsMargins[index] floatValue];
    }
    return self.itemMargin;
}

- (CGFloat)menuView:(WMMenuView *)menu titleSizeForState:(WMMenuItemState)state atIndex:(NSInteger)index {
    switch (state) {
        case WMMenuItemStateSelected: {
            return self.titleSizeSelected;
            break;
        }
        case WMMenuItemStateNormal: {
            return self.titleSizeNormal;
            break;
        }
    }
}

- (UIColor *)menuView:(WMMenuView *)menu titleColorForState:(WMMenuItemState)state atIndex:(NSInteger)index {
    switch (state) {
        case WMMenuItemStateSelected: {
            return self.titleColorSelected;
            break;
        }
        case WMMenuItemStateNormal: {
            return self.titleColorNormal;
            break;
        }
    }
}

#pragma mark - WMMenuViewDataSource
/**
 *  角标 (例如消息提醒的小红点) 的数据源方法，在 WMPageController 中实现这个方法来为 menuView 提供一个 badgeView
 需要在返回的时候同时设置角标的 frame 属性，该 frame 为相对于 menuItem 的位置
 *
 *  @param index 角标的序号
 *
 *  @return 返回一个设置好 frame 的角标视图
 */
- (UIView *)menuView:(WMMenuView *)menu badgeViewAtIndex:(NSInteger)index{
    UIView *view = nil;
    return view;
    
}
- (NSInteger)numbersOfTitlesInMenuView:(WMMenuView *)menu {
    return self.childControllersCount;
}

- (NSString *)menuView:(WMMenuView *)menu titleAtIndex:(NSInteger)index {
    return [self titleAtIndex:index];
}

@end
