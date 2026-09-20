---
layout: post
title: "Struct copying performance"
date: 2011-11-19 02:16:00
author: Aleksandr Shvedov
---
![Struct copying performance by size, layout, and architecture]({{ site.baseurl }}/images/struct-copy-perf.png)

The chart shows how the size of a value type affects copying performance, for example when passing values as method arguments or storing them in an array. A few observations:

* Alignment has a *significant* effect on copying performance. Despite the noise in the measurements, automatic layout consistently gives better results. Small, unaligned structs are much slower to copy than their aligned counterparts.
* On x86, performance drops sharply above 24 bytes, rather than the 16-byte maximum struct size often recommended in guidelines.
* Thanks to its wider registers, x64 does not suffer the same performance drop as x86 when the struct size increases.

Here is the benchmark code. It is a quick experiment rather than a polished benchmark:

```c#
using System;
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using System.Threading;

static class Program
{
  private static void Main()
  {
    Thread.CurrentThread.Priority = ThreadPriority.Highest;

    var name = new AssemblyName("FooAssembly");
    var module = AppDomain.CurrentDomain
      .DefineDynamicAssembly(name, AssemblyBuilderAccess.Run)
      .DefineDynamicModule("FooModule");

    for (var structSize = 0; structSize < 1000; structSize++)
    {
      Console.Write("{0};", structSize);

      foreach (var layoutMode in Layouts)
      {
        // generate a new struct type with the specified layout
        var typeName = Guid.NewGuid().ToString();
        var typeBuilder = module.DefineType(typeName, layoutMode |
          TypeAttributes.Class | TypeAttributes.BeforeFieldInit |
          TypeAttributes.Sealed, typeof(ValueType));

        // add the requested number of byte fields
        for (var i = 0; i < structSize; i++)
          typeBuilder.DefineField(
            "field" + i, typeof(byte), FieldAttributes.Public);

        // construct TestClass with the generated type as its type argument
        var testType = typeof(TestClass<>)
          .MakeGenericType(typeBuilder.CreateType());

        // run the benchmark
        var stopwatch = Stopwatch.StartNew();
        testType.GetMethod("DoTest").Invoke(null, null);
        Console.Write("{0};", stopwatch.Elapsed.TotalMilliseconds);
      }

      Console.WriteLine();
    }
  }

  private static readonly TypeAttributes[] Layouts =
  {
    TypeAttributes.SequentialLayout,
    TypeAttributes.AutoLayout
  };
}

static class TestClass<T> where T : struct
{
  private const int COUNT = 10000000;

  public static void DoTest()
  {
    var array = new T[1000];
    for (var i = 0; i < COUNT; i++)
    {
      var temp1 = new T();
      var temp2 = Foo1(temp1); // pass the value through the methods
      array[i % 1000] = temp2; // store the result in the array
    }
  }

  [MethodImpl(MethodImplOptions.NoInlining)]
  private static T Foo1(T x) { return Foo2(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  private static T Foo2(T x) { return Foo3(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  private static T Foo3(T x) { return Foo4(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  private static T Foo4(T x) { return Foo5(x); }
  [MethodImpl(MethodImplOptions.NoInlining)]
  private static T Foo5(T x) { return x; }
}
```