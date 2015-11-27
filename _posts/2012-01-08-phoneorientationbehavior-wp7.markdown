---
layout: post
title: "PhoneOrientationBehavior для WP7"
date: 2012-01-08 20:52:00
categories: 15516776088
author: Шведов Александр
tags: csharp wp7 .net behavior
---
По мере ~~ужасания~~ ковыряния API виндофончиков, рождаются ~~вело~~кусочки кода, претендующие на переиспользование. Начнём с behavior’а, который помогает скрывать те или иные элементу управления в альбомной ориентации WP7-девайса, так как большие отступы, всякие названия приложений и прочие элементы metro-дизайна просто нещадно кушают место на экране.

Начнём с базового класса:

```c#
using System.Windows;
using System.Windows.Interactivity;
using Microsoft.Phone.Controls;

public abstract class PhoneOrientationBehavior<T> : Behavior<T>
  where T : FrameworkElement
{
  bool isSubscribedWhenAttached;

  protected override void OnAttached() {
    base.OnAttached();

    // если behavior применён к startup-странице, то
    // RootVisual на данный момент будет инициализирован null'ом
    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null) {
      root.OrientationChanged += OrientationChanged;
      isSubscribedWhenAttached = true;
    }

    AssociatedObject.Loaded += ElementLoaded;
  }

  private void ElementLoaded(object sender, RoutedEventArgs e)
  {
    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null) {
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

  private void ApplyOrientation(PageOrientation orientation) {
    switch (orientation) {
      case PageOrientation.LandscapeRight:
      case PageOrientation.LandscapeLeft: {
        ApplyOrientation(false);
        break;
      }

      case PageOrientation.PortraitUp:
      case PageOrientation.PortraitDown: {
        ApplyOrientation(true);
        break;
      }
    }
  }

  protected abstract void ApplyOrientation(bool isPortrait);

  protected override void OnDetaching() {
    base.OnDetaching();

    var root = Application.Current.RootVisual as PhoneApplicationFrame;
    if (root != null) root.OrientationChanged -= OrientationChanged;

    AssociatedObject.Loaded -= ElementLoaded;
  }
}
```

Теперь можно определить наследника, реализующего сокрытие элементов управления в альбомной ориентации:

```c#
using System.Windows;

public sealed class PortraitOrientationVisibilityBehavior
  : PhoneOrientationBehavior<FrameworkElement>
{
  public bool Invert { get; set; }

  protected override void ApplyOrientation(bool isPortrait) {
    if (Invert) isPortrait = !isPortrait;

    AssociatedObject.Visibility = isPortrait
      ? Visibility.Visible
      : Visibility.Collapsed;
  }
}
```

Однако этот behavior не удастся применить, чтобы скрыть виндофоновый system tray и application bar (что может быть полезно, например, если он содержит лишь малозначимые пункты меню типа отправки feedback’а). Не проблема, создаём ещё одного наследника `PhoneOrientationBehavior` и применяем к `PhoneApplicationPage`'ам:

```c#
using Microsoft.Phone.Controls;
using Microsoft.Phone.Shell;

public sealed class PortraitOrientationSystemTrayVisibility
  : PhoneOrientationBehavior<PhoneApplicationPage>
{
  public bool HideApplicationBar { get; set; }

  protected override void ApplyOrientation(bool isPortrait) {
    SystemTray.SetIsVisible(AssociatedObject, isPortrait);
    if (HideApplicationBar)
      AssociatedObject.ApplicationBar.IsVisible = isPortrait;
  }
}
```

А вообще по-хорошему, надо разобраться с templated-контролами и сделать layout-контрол, позволяющий задавать два шаблона layout’ов (portrait и landscape, соответственно) с некими content placeholder’ами и наполнять его контентом - это может существенно упростить разработку UI, поддерживающего две ориентации экрана.