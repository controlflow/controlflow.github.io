---
layout: post
title: "Delegate equality: methods on value types (part 2)"
date: 2011-10-24 16:12:54
author: Aleksandr Shvedov
tags: csharp clr .net delegate valuetype
---
After the [previous post]({{ site.baseurl }}/2011/10/24/delegate-equality-base.html), here is another example:

```c#
using System;

struct Foo
{
  public void M() { Console.Write("uups!"); }
}

class Bar
{
  private static event Action E = delegate { };

  private static void Main()
  {
    var foo = new Foo();

    E += foo.M;
    E -= foo.M;

    E(); // ???
  }
}

```

Once again, the handler stays subscribed. Recreating a delegate from `foo.M` cannot remove it.

The cause is that `Foo` is a *value type*, and implicit *boxing* occurs both when subscribing *and* when attempting to unsubscribe. A delegate created from an instance method on a value type needs to retain its target, just as a delegate for a method on a class retains a reference to `this`. The delegate needs an object reference for that target, so the value is boxed. The delegate then keeps the boxed copy alive for as long as it is needed.

What happens when we try to unsubscribe? The value is boxed *again*. The two boxes are separate objects; neither carries any identity linking it to the original variable. `Delegate.Equals` compares these targets by reference. It does not use the value type's own equality rules, whether defined by an override of `Equals` or an implementation of `IEquatable<T>`. The methods match, but the target objects do not, so the delegate passed to `-=` is not equal to the subscribed delegate. Repeatedly converting `foo.M` to a delegate only creates more boxes.

To unsubscribe successfully, retain the delegate created when subscribing and pass that same instance to `-=`.