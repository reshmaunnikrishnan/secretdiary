//
//  Created by Matt Greenfield on 24/05/12
//  Copyright (c) 2012 Big Paua. All rights reserved
//  http://bigpaua.com/
//

#import "MGScrollView.h"
#import "MGLayoutManager.h"
#import "MGBoxProvider.h"

// default keyboardMargin
#define KEYBOARD_MARGIN 8

@implementation MGScrollView {
  CGFloat keyboardNudge;
  BOOL fixedPositionEstablished;
  BOOL asyncDrawing, asyncDrawOnceing;
  CGRect keyboardFrame;
}

// MGLayoutBox protocol
@synthesize boxes, boxProvider, boxPositions, parentBox;
@synthesize boxLayoutMode, contentLayoutMode;
@synthesize asyncLayout, asyncLayoutOnce, asyncQueue;
@synthesize margin, topMargin, bottomMargin, leftMargin, rightMargin;
@synthesize padding, topPadding, rightPadding, bottomPadding, leftPadding;
@synthesize attachedTo, replacementFor, sizingMode, minWidth;
@synthesize fixedPosition, zIndex, layingOut, slideBoxesInFromEmpty;
@synthesize dontLayoutChildren;

// MGLayoutBox protocol optionals
@synthesize tapper, tappable, onTap;

#pragma mark - Factories

+ (id)scroller {
  MGScrollView *scroller = [[self alloc] initWithFrame:CGRectZero];
  return scroller;
}

+ (id)scrollerWithSize:(CGSize)size {
  CGRect frame = CGRectMake(0, 50, size.width, size.height);
  MGScrollView *scroller = [[self alloc] initWithFrame:frame];
  return scroller;
}

#pragma mark - Init and setup

- (id)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  [self setup];
  return self;
}

- (id)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  [self setup];
  return self;
}

- (void)setup {

  // defaults
  self.keyboardMargin = KEYBOARD_MARGIN;
  self.keepFirstResponderAboveKeyboard = YES;
  self.viewportMargin = UIScreen.mainScreen.bounds.size;
  self.boxPositions = @[].mutableCopy;

  self.delegate = self;

  // watch for the keyboard
  [NSNotificationCenter.defaultCenter addObserver:self
      selector:@selector(keyboardWillAppear:) name:UIKeyboardWillShowNotification
      object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self
      selector:@selector(keyboardWillDisappear:)
      name:UIKeyboardWillHideNotification object:nil];
}

#pragma mark - Layout

- (void)layout {

  // box provider style layout
  if (self.boxProvider) {
    [self updateContentSize];
    [self.boxProvider updateVisibleIndexes];
    [MGLayoutManager layoutBoxesIn:self
        atIndexes:self.boxProvider.visibleIndexes];
    return;
  }

  [MGLayoutManager layoutBoxesIn:self];

  // async draws
  if (self.asyncLayout || self.asyncLayoutOnce) {
    dispatch_async(self.asyncQueue, ^{
      if (self.asyncLayout && !asyncDrawing) {
        asyncDrawing = YES;
        self.asyncLayout();
        asyncDrawing = NO;
      }
      if (self.asyncLayoutOnce && !asyncDrawOnceing) {
        asyncDrawOnceing = YES;
        self.asyncLayoutOnce();
        self.asyncLayoutOnce = nil;
        asyncDrawOnceing = NO;
      }
    });
  }
}

- (void)layoutWithSpeed:(NSTimeInterval)speed completion:(Block)completion {
  [MGLayoutManager layoutBoxesIn:self withSpeed:speed completion:completion];
}

- (void)layoutSubviews {

  // deal with fixed position
  for (UIView <MGLayoutBox> *box in self.subviews) {
    if ([box conformsToProtocol:@protocol(MGLayoutBox)] && box.boxLayoutMode
        == MGBoxLayoutFixedPosition) {
      box.y = box.fixedPosition.y + self.contentOffset.y;
    }
  }
}

- (void)updateContentSize {
  CGSize size = (CGSize){self.width, self.topPadding + self.bottomPadding};
  for (int i = 0; i < self.boxProvider.count; i++) {
    CGSize boxSize = [self.boxProvider sizeForBoxAtIndex:i];
    size.height += boxSize.height;
  }
  self.contentSize = size;
}

#pragma mark - Interaction

- (void)tapped {
  if (self.onTap) {
    self.onTap();
  }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recogniser
       shouldReceiveTouch:(UITouch *)touch {

  // say yes to UIScrollView's internal recognisers
  if (recogniser == self.panGestureRecognizer || recogniser
      == self.gestureRecognizers[0]) {
    return YES;
  }

  // say no if a UIControl got there first (iOS 6 makes this unnecessary)
  return ![touch.view isKindOfClass:UIControl.class];
}

#pragma mark - Scrolling

- (void)scrollToView:(UIView *)view withMargin:(CGFloat)_margin {
  CGRect frame = [self convertRect:view.frame fromView:view.superview];
  [self scrollRectToVisible:CGRectInset(frame, -_margin, -_margin) animated:YES];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (self.boxProvider) {
    [self.boxProvider updateVisibleIndexes];
    [MGLayoutManager layoutBoxesIn:self
        atIndexes:self.boxProvider.visibleIndexes];

    // Apple bug workaround
    self.showsVerticalScrollIndicator = NO;
    self.showsVerticalScrollIndicator = YES;
  }
}

#pragma mark - Edge snapping

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
  if (self.snapToBoxEdges) {
    [self snapToNearestBox];
  }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView
                  willDecelerate:(BOOL)decelerate {
  if (self.snapToBoxEdges && !decelerate) {
    [self snapToNearestBox];
  }
}

- (void)snapToNearestBox {
  if (self.contentSize.height <= self.frame.size.height) {
    return;
  }
  if ([self.boxes count] < 2) {
    return;
  }

  CGSize size = self.frame.size;
  CGPoint offset = self.contentOffset;
  CGFloat fromBottom = self.contentSize.height - (offset.y + size.height);
  CGFloat fromTop = offset.y;
  CGFloat newY = 0;

  // near the bottom? then snap to
  UIView *last = [self.boxes lastObject];
  if (fromBottom < last.frame.size.height / 2 && fromBottom < fromTop) {
    newY = self.contentSize.height - size.height;
  } else { // find nearest box
    CGFloat oldY = offset.y;
    CGFloat diff = self.contentSize.height;
    for (UIView *box in self.boxes) {
      if (ABS(box.frame.origin.y - self.bottomPadding - oldY) < diff) {
        diff = ABS(box.frame.origin.y - oldY);
        newY = box.frame.origin.y - self.bottomPadding;
      }
    }
  }

  [UIView animateWithDuration:0.1 animations:^{
    self.contentOffset = CGPointMake(0, newY);
  }];
}

#pragma mark - Dealing with the keyboard

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

- (void)keyboardWillAppear:(NSNotification *)note {

  // haven't been asked to deal with keyboard scrolling?
  if (!self.keepAboveKeyboard && !self.keepFirstResponderAboveKeyboard) {
    return;
  }

  // target, if given an explicit view to keep above keyboard
  UIView *view = self.keepAboveKeyboard;

  // target by finding a descendant that's first respondent
  if (!view && self.keepFirstResponderAboveKeyboard) {
    UIResponder *first = self.currentFirstResponder;
    if ([first isKindOfClass:UIView.class]
        && [(id)first isDescendantOfView:self]) {
      view = (id)first;
    } else {
      return;
    }
  }

  // target rect in local space
  CGRect target = [view.superview convertRect:view.frame toView:nil];

  // keyboard's frame
  if (note) {
    keyboardFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
  }

  // determine overage
  CGFloat targetBottom = target.origin.y + target.size.height;
  CGFloat over = targetBottom + self.keyboardMargin - keyboardFrame.origin.y;

  // need to nudge?
  keyboardNudge = over > 0 ? over : 0;
  if (keyboardNudge <= 0) {
    return;
  }

  // animate the scroll
  double d = note
      ? [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]
      : 0.1;
  int curve = note
      ? [note.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue]
      : UIViewAnimationCurveEaseInOut;
  [UIView animateWithDuration:d delay:0 options:curve animations:^{
    CGPoint offset = self.contentOffset;
    offset.y += over;
    self.contentOffset = offset;
  } completion:nil];
}

#pragma clang diagnostic warning "-Wdeprecated-declarations"

- (void)keyboardWillDisappear:(NSNotification *)note {
  double d = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
  int curve = [note.userInfo[UIKeyboardAnimationCurveUserInfoKey] intValue];
  [UIView animateWithDuration:d delay:0 options:curve animations:^{
    CGPoint offset = self.contentOffset;
    offset.y -= keyboardNudge;
    self.contentOffset = offset;
    keyboardNudge = 0;
  } completion:nil];
}

- (void)restoreAfterKeyboardClose:(Block)completion {
  if (!keyboardNudge) {
    if (completion) {
      completion();
    }
    return;
  }

  [UIView animateWithDuration:0.3 animations:^{
    CGPoint offset = self.contentOffset;
    offset.y -= keyboardNudge;
    self.contentOffset = offset;
    keyboardNudge = 0;
  } completion:^(BOOL fini) {
    if (completion) {
      completion();
    }
  }];
}

- (BOOL)                         gestureRecognizer:(UIGestureRecognizer *)me
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
  return self.scrollEnabled;
}

#pragma mark - Setters

- (void)setMargin:(UIEdgeInsets)_margin {
  self.topMargin = _margin.top;
  self.rightMargin = _margin.right;
  self.bottomMargin = _margin.bottom;
  self.leftMargin = _margin.left;
}

- (void)setPadding:(UIEdgeInsets)_padding {
  self.topPadding = _padding.top;
  self.rightPadding = _padding.right;
  self.bottomPadding = _padding.bottom;
  self.leftPadding = _padding.left;
}

- (void)setTappable:(BOOL)can {
  if (tappable == can) {
    return;
  }
  tappable = can;
  if (can) {
    [self addGestureRecognizer:self.tapper];
  } else if (self.tapper) {
    [self removeGestureRecognizer:self.tapper];
  }
}

- (void)setOnTap:(Block)_onTap {
  onTap = [_onTap copy];
  if (onTap) {
    self.tappable = YES;
  }
}

- (void)setBoxProvider:(MGBoxProvider *)provider {
  boxProvider = provider;
  provider.container = self;
}

#pragma mark - Getters

- (NSMutableArray *)boxes {
  if (!boxes) {
    boxes = @[].mutableCopy;
  }
  return boxes;
}

- (CGRect)bufferedViewport {
  UIEdgeInsets buffer = UIEdgeInsetsMake(-self.viewportMargin.height,
      -self.viewportMargin.width, -self.viewportMargin.height,
      -self.viewportMargin.width);
  return CGRectOffset(UIEdgeInsetsInsetRect(self.frame, buffer),
      self.contentOffset.x, self.contentOffset.y);
}

- (UIEdgeInsets)margin {
  return UIEdgeInsetsMake(self.topMargin, self.leftMargin, self.bottomMargin,
      self.rightMargin);
}

- (UIEdgeInsets)padding {
  return UIEdgeInsetsMake(self.topPadding, self.leftPadding, self.bottomPadding,
      self.rightPadding);
}

- (CGPoint)fixedPosition {
  if (!fixedPositionEstablished) {
    fixedPosition = self.frame.origin;
    fixedPositionEstablished = YES;
  }
  return fixedPosition;
}

- (dispatch_queue_t)asyncQueue {
  if (!asyncQueue) {
    asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  }
  return asyncQueue;
}

- (UITapGestureRecognizer *)tapper {
  if (!tapper) {
    tapper = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(tapped)];
    tapper.delegate = self;
  }
  return tapper;
}

#pragma mark - Fini

- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
