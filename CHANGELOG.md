
## 淘头条项目结合频道管理，做出了加载过的页面不必加载，频道选择完毕后用缓存刷新整体结构的方式

## [2.4.3 [BUGFIXS]()
### Remove observer / Cancel performSelector when dealloc.
### -initWithNib supoort.

## [2.4.1 [BUGFIXS]](https://github.com/wangmchn/WMPageController/releases/tag/2.4.1)
### FIX [#286](https://github.com/wangmchn/WMPageController/issues/286), Layout Stragety adjusted. 

- Now: WMPageController will layout every time when `-viewDidLayoutSubviews` called.
- Before: Early returned if `self.view.frame.size.height` is not changed.

## [2.4.0 [API CHANGED][BETA]]()
**[IMPORTANT] WMPAGECONTROLLER ARE NO LONGER ADAPT VIEW'S FRAMES & SOME GESTURES CONFLICTS!!**
### [DELETE] Some properties have been deleted.
- `viewFrame / menuHeight / menuBGColor / menuViewBottomSpace / otherGestureRecognizerSimultaneously`
### [ADD] Two datasource methods have been added.
- `-pageController:preferredFrameForMenuView:` 
- `-pageController:preferredFrameForContentView:`
### [GUIDE]
- If you want a right frame of menuView or contentView, implement `-pageController:preferredFrameForMenuView: & -pageController:preferredFrameForContentView:` methods and give WMPageController a right frame.
- Call `-forceLayoutSubViews` to re-layout view's frames, these will recall the datasource methods above.
- Change menuView's backgroundColor by setting `self.menuView.backgroundColor = perferredColor` directly.(AFTER THE VIEW IS LOADED, e.g. in viewDidLoad)
- Deal gesture's conflicts by implement `UIGestureRecognizerDelegate` IF NEEDED, see [UIGestureRecognizerDelegate](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate) for more information.

## [1.0.0 ~ 2.3.1 [OLD VERSION]]()
**OLD VERSION & NO LONGER MAINTAIN**
