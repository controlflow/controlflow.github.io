---
layout: post
title: "Необработанные исключения из потока GC в CLR"
date: 2011-11-21 01:23:15
author: Шведов Александр
tags: csharp clr dotnet .net gc exceptions
---
Известная проблема в CLR, приводящий к необработанному исключению в потоке сборщика мусора:

```c#
using System;
using System.Threading;

sealed class Foo {
  static Foo() { throw new Exception(".cctor"); }
  public Foo() { Console.WriteLine("Foo()"); }
  ~Foo() { Console.WriteLine("~Foo"); }
}

static class Program {
  static void Main() {
    Console.WriteLine(
      "@Main thread: {0}", Thread.CurrentThread.ManagedThreadId);

    AppDomain.CurrentDomain.UnhandledException += (_, e) =>
      Console.WriteLine("Unhandled! (@Thread: {0})\n{1}\n",
        Thread.CurrentThread.ManagedThreadId, e.ExceptionObject);

    try { new Foo(); } // вызываем TypeInitializationException
    catch (TypeInitializationException e) {
      Console.WriteLine("Handled in main\n{0}\n", e);
    }

    // а теперь попробуем собрать мусор
    Console.WriteLine("Collecting garbage...");
    GC.Collect();
    GC.WaitForPendingFinalizers(); // <= важно

    Console.WriteLine("Finish");
  }
}
```

Происходит тут следующее: производится попытка создать экземпляр типа Foo, что приводит к вызову статического конструктора, который бросает исключение. Всё это приводит к исключению `TypeInitializationExeption` (в свойстве `InnerException` которого содержится оригинальное исключение, произошедшее в статическом конструкторе) и тип `Foo` становится “испорченным”, до конца жизни домена - все вызовы его статических методов или попытки создать экземпляр будут заканчиваться тем же экземпляром `TypeInitializationException`.

Однако разработчики CLR не учли, что в случае создания нового экземпляра типа Foo, не смотря на исключение в статическом конструкторе, память под экземпляр всё же выделяется и не инициализированный экземпляр становится предметом сборки мусора (кстати, объекты в .NET могут быть собраны GC даже во время исполнения собственного конструктора). Так как объект определяет финализатор, а сам финализатор является обычным виртуальным методом, унаследованным от `System.Object`, то при его вызове необходима инициализация типа - вызов статического конструктора - которая опять же падает по `TypeInitializationException`, только теперь это происходит в потоке GC.

Пример, конечно же, очень синтетический, но заставляет задуматься о том, что нужно сделать с разработчиком, решившим обработать исклю&shy;чение `TypeInitializationException`.