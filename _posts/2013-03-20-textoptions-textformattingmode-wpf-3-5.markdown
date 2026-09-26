---
layout: post
title: "TextOptions.TextFormattingMode and WPF 3.5"
date: 2013-03-20 13:04:00
author: Aleksandr Shvedov
---
The text rendering quality in WPF and Silverlight had always bothered me. Fortunately, WPF 4.0 introduced the [`TextOptions.TextFormattingMode`](http://msdn.microsoft.com/en-us/library/system.windows.media.textoptions.textformattingmode.aspx) attached property. Setting it to `Display` produces text that looks indistinguishable from GDI rendering. Unfortunately, applications targeting WPF 3.5 cannot use this property directly, even if they usually run under WPF 4.0. Reflection provides a workaround, so I thought I would share this small helper:

```c#
public enum TextFormattingModeWPF4 { Ideal, Display }

public static class TextOptionsWPF4
{
  public static readonly DependencyProperty TextFormattingModeProperty;
  static TextOptionsWPF4()
  {
    try
    {
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
    finally
    {
      TextFormattingModeProperty = TextFormattingModeProperty ??
        DependencyProperty.RegisterAttached(
          "TextFormattingMode", typeof(TextFormattingModeWPF4), typeof(TextOptionsWPF4),
          new PropertyMetadata(TextFormattingModeWPF4.Ideal));
    }
  }

  public static TextFormattingModeWPF4 GetTextFormattingMode(UIElement element)
  {
    return (TextFormattingModeWPF4) element.GetValue(TextFormattingModeProperty);
  }

  public static void SetTextFormattingMode(UIElement element, TextFormattingModeWPF4 value)
  {
    var val = Enum.ToObject(TextFormattingModeProperty.PropertyType, (int)value);
    element.SetValue(TextFormattingModeProperty, val);
  }
}
```