---
layout: post
title: "Delegate equality: delegates from interface methods (part 3)"
date: 2011-11-14 14:12:31
author: Aleksandr Shvedov
tags: csharp clr delegate .net interface
---
Continuing the discussion of delegate equality, here is another subtle case that [Vladimir Reshetnikov](https://github.com/VladimirReshetnikov) kindly pointed out to me. The [case involving `base.` calls]({{ site.baseurl }}/2011/10/24/delegate-equality-base.html) is not the only situation where the C# compiler generates wrapper methods that can affect delegate equality. Consider this example:

```c#
using System;

interface IFoo
{
  void Bar();
}

class Foo : IFoo
{
  public void Bar()
  {
    Console.WriteLine("Foo.Bar()");
  }
}

static class Boo
{
  private static event Action E = delegate { };

  private static void Main()
  {
    var foo = new Foo();
    IFoo ifoo = foo;

    E += foo.Bar;  // subscribe using the class method
    E -= ifoo.Bar; // unsubscribe using the interface method

    E(); // ???
  }
}
```

This behaves as expected: nothing is printed, because the handler is successfully removed. Creating a delegate from an interface method involves *virtual dispatch*, much like calling the method. The runtime resolves the actual method that implements the interface, and that is the method the delegate targets. This lookup makes delegate creation slightly slower than for an ordinary non-virtual method.

Now let us move the implementation into a base class in a separate assembly, `FooLibrary.dll`:

```c#
using System;

namespace FooLibrary
{
  public class Foo
  {
    public void Bar()
    {
      Console.WriteLine("Foo.Bar()");
    }
  }
}
```

The derived class implements the interface implicitly using the inherited method:

```c#
using System;

interface IFoo
{
  void Bar();
}

class DerivedFoo : FooLibrary.Foo, IFoo
{
  // the base class method implements IFoo.Bar
}

static class Boo
{
  private static event Action E = delegate { };

  private static void Main()
  {
    var foo = new DerivedFoo();
    IFoo ifoo = foo;

    E += foo.Bar;
    E -= ifoo.Bar;

    E(); // ???
  }
}
```

This version prints `Foo.Bar()`: the handler is no longer removed. Now move the base class and the derived class into the same assembly:

```c#
using System;

interface IFoo
{
  void Bar();
}

public class Foo
{
  public void Bar()
  {
    Console.WriteLine("Foo.Bar()");
  }
}

class DerivedFoo : Foo, IFoo
{
  // the base class method implements IFoo.Bar
}

static class Boo
{
  private static event Action E = delegate { };

  private static void Main()
  {
    var foo = new DerivedFoo();
    IFoo ifoo = foo;

    E += foo.Bar;
    E -= ifoo.Bar;

    E(); // ???
  }
}
```

Once again, there is no output. What changed?

At the CLI level, a method that implements an interface must be virtual: it needs the `virtual` flag in its metadata and a slot in the virtual method table. The C# compiler adds this flag to methods declared `virtual` in C#, but that is not the only case. When a non-virtual C# method implements an interface, the compiler marks it as both `virtual` and `final` in IL. The `final` flag prevents overriding, much like `sealed` does for methods in C#. This gives the method a slot in the virtual method table; it does not mean that every call to an implicit interface implementation uses virtual dispatch.

The compiler cannot always do this directly. A class can implement an interface using a suitable inherited method, even if that method was declared without `virtual` and did not originally implement any interface. This is the situation in the last two examples.

The C# compiler has two ways to handle it. It can adjust the metadata of the base class, marking the method `virtual final` in IL, or it can generate a `virtual final` wrapper in the derived class that calls the base method. The compiler prefers the first approach when the base class is part of the same compilation and is being emitted into the same assembly.

This explains the failure with separate assemblies. The delegate used to unsubscribe targets a wrapper in `DerivedFoo`, rather than `Foo.Bar()`, because the compiler cannot change the metadata in the external assembly. Declaring the base class method `virtual` avoids the wrapper and restores the expected delegate equality.