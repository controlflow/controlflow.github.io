---
layout: post
title: "CLR return type covariance"
date: 2010-10-01 13:25:31
author: Aleksandr Shvedov
tags: csharp covariance override
---
Until today, for some reason, I was convinced that the CLR supported return type covariance when overriding virtual methods, and that C# just hadn't gotten around to adding this little feature... Turns out the .NET Framework runtime doesn't support it either: the return types have to match exactly. Here's the proof:

```c#
using System;
using System.Reflection;
using System.Reflection.Emit;

public abstract class Foo {
  public abstract Foo Bar();

  private static void Main() {
    // create a dynamic assembly with a module
    var dynAssembly = AppDomain.CurrentDomain
      .DefineDynamicAssembly(
        name: new AssemblyName("FooAssembly"),
        access: AssemblyBuilderAccess.RunAndCollect);

    var dynModule = dynAssembly.DefineDynamicModule("FooModule");

    // define a type derived from Foo
    var dynType = dynModule.DefineType(
      "FooDerived", TypeAttributes.Public, typeof(Foo));

    // generate a default constructor
    dynType.DefineDefaultConstructor(MethodAttributes.Public);

    // generate an overriding method
    var method = dynType.DefineMethod("Bar",
      MethodAttributes.Public | MethodAttributes.Virtual,
      CallingConventions.Standard, dynType, Type.EmptyTypes);

    // emit the body { return this; }
    var il = method.GetILGenerator();
    il.Emit(OpCodes.Ldarg_0);
    il.Emit(OpCodes.Ret);

    // declare the override
    dynType.DefineMethodOverride(
      method, typeof(Foo).GetMethod("Bar"));

    // create the type and instantiate it
    var derivedType = dynType.CreateType(); // FUUUUUUUUUUUU
    var foo = (Foo) Activator.CreateInstance(derivedType);

    // call the method
    Console.WriteLine(foo.Bar());
  }
}
```

On the other hand, `Delegate.CreateDelegate()` supports both return type covariance and parameter type contravariance when creating delegates from `MethodInfo` instances. No variance annotations on the delegate type are needed, and this even works in .NET Framework 2.0. I suspect this was added so that `Delegate.CreateDelegate()` would reproduce at runtime what C# already does at compile time: support for covariance and contravariance when converting a method group to a delegate type:

```c#
using System;

// expected `object Method(string)`
// got `string Method(object)`
Func<string, object> func = Method; // compiles fine!

private string Method(object arg) { return arg.ToString(); }
```

p.s. Covariant return type overrides later appeared in C# 9.0 and .NET 5 runtime, 11 years later after this post was published.