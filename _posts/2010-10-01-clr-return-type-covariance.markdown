---
layout: post
title: "CLR и return type covariance"
date: 2010-10-01 13:25:31
categories: 1221149165
tags: csharp covariance override
---
До сегоднешнего дня я почему-то был уверен, что runtime CLR поддерживает ковариантность типа возвращаемого значения при переопределении виртуальных методов, просто в C# эту мелоч никак не засунут… Оказалось, что нет, не поддерживает и требует точного совпадения типов, пруф:

{% highlight C# %}
using System;
using System.Reflection;
using System.Reflection.Emit;

public abstract class Foo {
  public abstract Foo Bar();

  static void Main() {
    // создаём динамическую сборочку с модулем
    var dynAssembly = AppDomain.CurrentDomain
      .DefineDynamicAssembly(
        name: new AssemblyName("FooAssembly"),
        access: AssemblyBuilderAccess.RunAndCollect);

    var dynModule = dynAssembly.DefineDynamicModule("FooModule");

    // создаёт тип наследника Foo
    var dynType = dynModule.DefineType(
      "FooDerived", TypeAttributes.Public, typeof(Foo));

    // генерим дефолтный конструктор
    dynType.DefineDefaultConstructor(MethodAttributes.Public);

    // генерим override-метод
    var method = dynType.DefineMethod("Bar",
      MethodAttributes.Public | MethodAttributes.Virtual,
      CallingConventions.Standard, dynType, Type.EmptyTypes);

    // генерируем тело { return this; }
    var il = method.GetILGenerator();
    il.Emit(OpCodes.Ldarg_0);
    il.Emit(OpCodes.Ret);

    // объявляем переопределение
    dynType.DefineMethodOverride(
      method, typeof(Foo).GetMethod("Bar"));

    // компилим тип и создаём экземпляр
    var derivedType = dynType.CreateType(); // FUUUUUUUUUUUU
    var foo = (Foo) Activator.CreateInstance(derivedType);

    // вызываем
    Console.WriteLine(foo.Bar());
  }
}
{% endhighlight %}

Зато `Delegate.CreateDelegate()` поддерживает и коваринтность типа возвращаемого значения, и контравариантность типов параметров при создании делегатов из экземпляров `MethodInfo`. Причём аннотации вариантности на типе делегата совершенно не нужны, работает и в 2.0. Думаю поддержку сделали чтобы `Delegate.CreateDelegate()` повторял в рантайме статическое поведение C#, который поддерживает ко-/контравариантность при приведении method group к типу делегата :))