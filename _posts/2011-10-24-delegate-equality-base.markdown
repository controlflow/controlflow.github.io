---
layout: post
title: "Delegate equality: the base. qualifier (part 1)"
date: 2011-10-24 14:14:00
author: Aleksandr Shvedov
tags: csharp clr .net delegate base
---
What do you think this code prints?

```c#
using System;
using System.Collections.Generic;
using System.Linq;

// a class with an event
class Boo
{
  public event Action Event = delegate { };
  public void FireEvent() { Event(); }
}

// a class with a virtual method
class FooBase
{
  public virtual void Bar()
  {
    Console.WriteLine("FooBase.Bar");
  }
}

// a derived class that does not override Bar
class Foo : FooBase
{
  public void Unsubscribe(Boo boo)
  {
    // unsubscribe base.Bar from Boo.Event
    Action f = () => boo.Event -= base.Bar;
    f();
  }

  public IEnumerable<int> OnceAgain(Boo boo)
  {
    // unsubscribe again, this time inside an iterator
    boo.Event -= base.Bar;
    yield break;
  }
}

class Program
{
  private static void Main()
  {
    var foo = new Foo();
    var boo = new Boo();

    boo.Event += foo.Bar; // subscribe

    foo.Unsubscribe(boo); // try to unsubscribe twice
    foo.OnceAgain(boo).ToList();

    boo.FireEvent(); // ?
  }
}

```

It seems reasonable to expect no output: we appear to be unsubscribing the same method, `FooBase.Bar`, that we originally subscribed. Although the delegate instance used to unsubscribe is different, that should not matter. `System.Delegate` overrides `Equals` and `GetHashCode`; in this case, two delegates are equal if they refer to the same method on the same target object.

With C# compilers before version 4.0, this code does indeed print nothing. Starting with the C# 4.0 compiler, however, *neither attempt to unsubscribe succeeds*: not the lambda in `Unsubscribe`, nor the iterator. The program prints `FooBase.Bar`, which is surprising, to say the least.

The key is the `base` qualifier. A call to the base implementation of a virtual method is *non-virtual*. This is necessary because the virtual method table may point to an override in the derived class instead of the base implementation. If a call to `base.Bar()` from an override went through that table, it would call the override again, resulting in endless recursion. Incidentally, `base` calls are allowed in *any instance method*, not just in overrides. It took me a while to realize that.

The CLI permits this non-virtual access to virtual methods, but verifiability imposes an important restriction on these base calls: they must originate in a type derived from the type that declares the virtual method.

Now return to the example. The references to `base.Bar` do not end up directly inside the class derived from `FooBase`. For anonymous methods that capture local variables, and for iterators, the C# compiler generates helper types and moves the relevant code into their methods. References through `base` can move along with it. The resulting code may run, but it fails verification by `PEVerify`, because those helper types do not derive from `FooBase`. This is what happened with C# compilers before version 4.0.

The C# 4.0 compiler fixed this in a straightforward way: it adds an instance wrapper method to the derived class, and that wrapper performs the actual `base` call. The CLI restrictions are satisfied and the generated code becomes verifiable. However, the fix has an unfortunate side effect when a delegate is created from a method group qualified with `base`. The compiler uses the wrapper in this case too, so the delegate refers to the wrapper rather than to the original base method.

Delegate equality normally lets us unsubscribe without keeping the original delegate instance. Here, though, the two delegates refer to different instance methods, so they are unequal and the handler remains subscribed. One workaround is to add an ordinary instance method to the derived class that constructs and returns the delegate for `base.Bar`, then call that helper from the lambda or iterator.

This is a good reason to avoid using method groups qualified with `base` to subscribe or unsubscribe inside lambdas and iterators: seemingly equivalent delegates may not be equal at all.