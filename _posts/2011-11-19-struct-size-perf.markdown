---
layout: post
title: "Скорость копирования структур"
date: 2011-11-19 02:16:00
author: Шведов Александр
---
![]({{ site.baseurl }}/images/struct-copy-perf.png)

График зависимости между размером типов-значений и скорости их копирования, например, при передаче в качестве параметров методов или сохранении в массиве типов-значений. Некоторые выводы:

* Выравнивание очень важно и *значительно* влияет на производительность копирования. Не смотря на шум в результатах, прекрасно видно, что automatic layout всегда даёт лучший результат. Не выровненные структуры небольших размеров просто адски тормозят по сравнению со своими выровненными аналогами.
* Значительный провал производительности на платформе x86 происходит при размерах более 24 байт, а не более 16 байт - самого часто упоминаемого рекомендуемого максимального размера структуры во всяческих гайдлайнах.
* За счёт большого размера регистров, платформа x64 не испытывает такой деградации производительности при увлечении размера структуры, какая проявляется на платформе x86.

Код теста (warning, написано на коленке):

```c#
using System;
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using System.Threading;

static class Program
{
  static void Main() {
    Thread.CurrentThread.Priority = ThreadPriority.Highest;

    var name = new AssemblyName("FooAssembly");
    var module = AppDomain.CurrentDomain
      .DefineDynamicAssembly(name, AssemblyBuilderAccess.Run)
      .DefineDynamicModule("FooModule");

    for (var structSize = 0; structSize < 1000; structSize++) {
      Console.Write("{0};", structSize);

      foreach (var layoutMode in Layouts) {
        // генерируем новый struct-тип с заданным режимом layout'а
        var typeName = Guid.NewGuid().ToString();
        var typeBuilder = module.DefineType(typeName, layoutMode |
          TypeAttributes.Class | TypeAttributes.BeforeFieldInit |
          TypeAttributes.Sealed, typeof(ValueType));

        // добавляем в тип n полей типа byte
        for (var i = 0; i < structSize; i++)
          typeBuilder.DefineField(
            "field" + i, typeof(byte), FieldAttributes.Public);

        // создаём тип TestClass, параметризованный новым типом
        var testType = typeof(TestClass<>)
          .MakeGenericType(typeBuilder.CreateType());

        // запускаем сам тест
        var stopwatch = Stopwatch.StartNew();
        testType.GetMethod("DoTest").Invoke(null, null);
        Console.Write("{0};", stopwatch.Elapsed.TotalMilliseconds);
      }

      Console.WriteLine();
    }
  }

  private static readonly TypeAttributes[] Layouts = {
    TypeAttributes.SequentialLayout,
    TypeAttributes.AutoLayout
  };
}

static class TestClass<T> where T : struct {
  private const int COUNT = 10000000;

  public static void DoTest() {
    var array = new T[1000];
    for (var i = 0; i < COUNT; i++) {
      var temp1 = new T();
      var temp2 = Foo1(temp1); // пропускаем через методы
      array[i % 1000] = temp2; // сохраняем в массив
    }
  }

  [MethodImpl(MethodImplOptions.NoInlining)]
  static T Foo1(T x) { return Foo2(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static T Foo2(T x) { return Foo3(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static T Foo3(T x) { return Foo4(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static T Foo4(T x) { return Foo5(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  static T Foo5(T x) { return x; }
}
```