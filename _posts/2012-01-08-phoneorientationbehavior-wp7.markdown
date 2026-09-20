---
layout: post
title: "PhoneOrientationBehavior for WP7"
date: 2012-01-08 20:52:00
author: Aleksandr Shvedov
tags: csharp wp7 .net behavior
---
As I explore the Windows Phone APIs, I keep finding small pieces of code worth reusing. Here is a behavior that hides selected controls when a WP7 device is in landscape orientation: generous margins, application titles, and other elements of the Metro design language can take up a substantial amount of the available screen space.

Let us start with the base class:

```c#
using System.Windows;
using System.Windows.Interactivity;
using Microsoft.Phone.Controls;

public abstract class PhoneOrientationBehavior<T> : Behavior<T>
  where T : FrameworkElement
{
  private bool isSubscribedWhenAttached;

  protected override void OnAttached()
  {
    base.OnAttached();

    // if the behavior is attached to the startup page,
    // the RootVisual property is still null at this point
    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null)
    {
      root.OrientationChanged += OrientationChanged;
      isSubscribedWhenAttached = true;
    }

    AssociatedObject.Loaded += ElementLoaded;
  }

  private void ElementLoaded(object sender, RoutedEventArgs e)
  {
    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null)
    {
      if (!isSubscribedWhenAttached)
        root.OrientationChanged += OrientationChanged;

      ApplyOrientation(root.Orientation);
    }

    AssociatedObject.Loaded -= ElementLoaded;
  }

  private void OrientationChanged(object sender, OrientationChangedEventArgs e)
  {
    ApplyOrientation(e.Orientation);
  }

  private void ApplyOrientation(PageOrientation orientation)
  {
    switch (orientation)
    {
      case PageOrientation.LandscapeRight:
      case PageOrientation.LandscapeLeft:
      {
        ApplyOrientation(false);
        break;
      }

      case PageOrientation.PortraitUp:
      case PageOrientation.PortraitDown:
      {
        ApplyOrientation(true);
        break;
      }
    }
  }

  protected abstract void ApplyOrientation(bool isPortrait);

  protected override void OnDetaching()
  {
    base.OnDetaching();

    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null) root.OrientationChanged -= OrientationChanged;

    AssociatedObject.Loaded -= ElementLoaded;
  }
}
```

We can now derive a behavior that hides controls in landscape orientation:

```c#
using System.Windows;

public sealed class PortraitOrientationVisibilityBehavior
  : PhoneOrientationBehavior<FrameworkElement>
{
  public bool Invert { get; set; }

  protected override void ApplyOrientation(bool isPortrait)
  {
    if (Invert) isPortrait = !isPortrait;

    AssociatedObject.Visibility = isPortrait
      ? Visibility.Visible
      : Visibility.Collapsed;
  }
}
```

This behavior cannot hide the Windows Phone system tray or application bar. Hiding the latter can be useful when it contains only secondary menu items, such as an option to send feedback. We can handle both by deriving another behavior from `PhoneOrientationBehavior` and attaching it to a `PhoneApplicationPage`:

```c#
using Microsoft.Phone.Controls;
using Microsoft.Phone.Shell;

public sealed class PortraitOrientationSystemTrayVisibility
  : PhoneOrientationBehavior<PhoneApplicationPage>
{
  public bool HideApplicationBar { get; set; }

  protected override void ApplyOrientation(bool isPortrait)
  {
    SystemTray.SetIsVisible(AssociatedObject, isPortrait);
    if (HideApplicationBar)
      AssociatedObject.ApplicationBar.IsVisible = isPortrait;
  }
}
```

A more flexible approach would be to explore templated controls and build a layout control with separate portrait and landscape templates. Each template could provide placeholders for the same content. This could make it much easier to build interfaces that support both screen orientations.