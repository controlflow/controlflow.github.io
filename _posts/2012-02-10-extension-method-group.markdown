---
layout: post
title: "Delegate from an extension method group"
date: 2012-02-10 19:04:00
author: Aleksandr Shvedov
tags: csharp delegate
---
I expected the C# compiler to generate a hidden closure for the following code:

```c#
static class Foo
{
  private static void Bar(this string source) { }

  private static void Main()
  {
    System.Action boo = "abc".Bar;
  }
}

```

Instead, the compiler emits the same IL for creating the delegate as it would if `Bar()` were an instance method on `System.String`. The delegate stores the string instance and supplies it as the first argument, just as an ordinary instance-method delegate stores and supplies the implicit `this` argument. Unfortunately, this trick do not works for the `this` parameters of the value type, C# rejects method groups like this (since boxing is required to attach the value to the delegate instance, and boxing observably copies the value - delegate invocation will invoke the instance struct method over the boxed copy, not the original value).

I would also like to have the ability to express the reverse operation: creating a delegate from an instance member without binding it to a particular object, and supplying the receiver as the delegate's first argument instead. There seems to be no conflict with static method names, either. For example, a property getter could be exposed using hypothetical syntax like this:

```c#
System.Func<string, int> boo = System.String.Length;
```

Virtual methods, however, raise an immediate question:

```c#
System.Func<Foo, int> boo = Foo.GetHashCode;
```

Which implementation should the delegate invoke? `Foo.GetHashCode()`? If `Foo` does not override it, should that be `Object.GetHashCode()`? What if the delegate's first argument is an instance of a subclass of `Foo` that provides its own override? Should that override be called, meaning that the delegate is not bound to one particular implementation? Or should it call the implementation on `Foo`, allowing callers to bypass the subclass override even when doing so might be inappropriate?

Should this syntax be allowed when `GetHashCode()` is abstract? Like any other virtual method, `Object.GetHashCode()` can be overridden and made abstract at the same time by combining the `abstract` and `override` modifiers. How should that case work?

All of this makes me question whether the feature would be worthwhile.