---
layout: post
title: "TextOptions.TextFormattingMode и WPF 3.5"
date: 2013-03-20 13:04:00
author: Aleksandr Shvedov
---
Меня всегда убивало качество шрифтов в WPF и Silverlight, но слава Вселенной, что с приходом WPF 4.0 появилось замечательное attached-свойство [`TextOptions.TextFormattingMode`](http://msdn.microsoft.com/en-us/library/system.windows.media.textoptions.textformattingmode.aspx), задав которое в значение `Display` можно получить качество шрифтов, неотличимое от GDI’ного. Однако по понятным причинам им невозможно воспользоваться в приложениях, собранных под WPF 3.5, но запускающихся в большинстве случаев под WPF 4.0, что крайне обидно. Решается рефлексией и утилкой, которой мне зачем-то захотелось с вами поделиться:

```c#
public enum TextFormattingModeWPF4 { Ideal, Display }

public static class TextOptionsWPF4 {
  public static readonly DependencyProperty TextFormattingModeProperty;
  static TextOptionsWPF4() {
    try {
      // PresentationFramework.dll
      var assembly = typeof(System.Windows.Application).Assembly;
      var textOptionsType = assembly.GetType("System.Windows.Media.TextOptions");
      if (textOptionsType == null) return;

      var property = textOptionsType.GetField(
        "TextFormattingModeProperty", BindingFlags.Public | BindingFlags.Static);
      if (property == null) return;

      TextFormattingModeProperty = property.GetValue(null) as DependencyProperty;
    }
    catch (Exception) { }
    finally {
      TextFormattingModeProperty = TextFormattingModeProperty ??
        DependencyProperty.RegisterAttached(
          "TextFormattingMode", typeof(TextFormattingModeWPF4), typeof(TextOptionsWPF4),
          new PropertyMetadata(TextFormattingModeWPF4.Ideal));
    }
  }

  public static TextFormattingModeWPF4 GetTextFormattingMode(UIElement element) {
    return (TextFormattingModeWPF4) element.GetValue(TextFormattingModeProperty);
  }

  public static void SetTextFormattingMode(UIElement element, TextFormattingModeWPF4 value) {
    var val = Enum.ToObject(TextFormattingModeProperty.PropertyType, (int)value);
    element.SetValue(TextFormattingModeProperty, val);
  }
}
```