---
layout: post
title: "A trick for caching expression trees"
date: 2011-09-06 09:00:06
author: Aleksandr Shvedov
tags: csharp expressions linq INotifyPropertyChanged mvvm
---
I often come across techniques in .NET blogs that use C# expression trees. Most extract a `MethodInfo`, `PropertyInfo`, or `FieldInfo` from an expression that accesses the corresponding member, or simply retrieve the member's name. For example, an implementation of `INotifyPropertyChanged` can replace string literals such as `OnChanged("PropertyName")` with lambda expressions such as `OnChanged(x => x.PropertyName)`, gaining compile-time checks and support for automated refactoring.

The problem is how these trees are constructed at runtime. Consider this code:

```c#
class Foo
{
  public int Value { get; set; }

  public Expression<Func<Foo, int>> Bar()
  {
    return x => x.Value;
  }
}
```

The C# compiler expands it into something like the following. This is illustrative pseudocode, not valid C#: the generated IL uses `ldtoken` to obtain a handle to `get_Value()`, the property's getter, and then retrieves its `MethodInfo`. C# could express similar code directly if it supported equivalents of `typeof()` for methods, properties, and fields:

```c#
class Foo
{
  public int Value { get; set; }

  public Expression<Func<Foo, int>> Bar()
  {
    var parameterExpression = Expression.Parameter(typeof(Foo), "x");
    return Expression.Lambda<Func<Foo, int>>(
      body: Expression.Property(
        expression: parameterExpression,
        propertyAccessor: (MethodInfo)
          MethodBase.GetMethodFromHandle(ldtoken(get_Value()))),
      parameters:
        new ParameterExpression[] { parameterExpression });
  }
}
```

All of this runs every time the seemingly simple lambda expression `x => x.Value` is converted to an expression tree. It involves several heap allocations and numerous type checks while constructing the tree, so the cost is far from negligible.

This construction overhead is acceptable in some cases, but not all. For example, in the WPF/Silverlight MVVM pattern, one reason to implement `INotifyPropertyChanged` in a view model instead of deriving from `DependencyObject` and using dependency properties is performance. Introducing expression trees can erase that advantage.

Interestingly, the C# compiler [caches delegates]({{ site.baseurl }}/2010/10/15/c-cachedanonymousmethoddelegate.html) when they capture no outer variables, but does not apply similar caching to expression trees, even though they are immutable too. If you have thoughts on why expression trees cannot be cached in the same way, please leave a comment. Here, I will explore how to implement such caching with a deliberately unconventional trick.

Let us start with a method that validates a property-access expression and returns the corresponding `PropertyInfo`:

```c#
using System;
using System.Linq.Expressions;
using System.Reflection;

public static class Property
{
  public static PropertyInfo Of<T, TProperty>(Expression<Func<T, TProperty>> propertyExpression)
  {
    if (propertyExpression == null)
      throw new ArgumentNullException("propertyExpression");

    var memberExpr = propertyExpression.Body as MemberExpression;
    if (memberExpr == null)
      throw new ArgumentException("MemberExpression expected");

    if (memberExpr.Member.MemberType != MemberTypes.Property)
      throw new ArgumentException("Property member expected");

    return (PropertyInfo) memberExpr.Member;
  }
}
```

The trick is to accept an ordinary delegate of type `Func<Expression<…>>` instead of an `Expression<…>` directly: a function that constructs the tree. The caller passes `() => x => x.Property` instead of `x => x.Property`. This moves the tree-construction code into the delegate's method, reducing the amount of IL at the call site. It also lets us invoke the delegate just once and cache the resulting tree. Since the compiler caches the delegate, subsequent calls from that site pass the same instance, which could serve as a key in a dictionary mapping delegates to expression trees.

There is also a way to avoid the dictionary entirely. Here is a version that caches the resulting `PropertyInfo`:

```c#
using System;
using System.Linq.Expressions;
using System.Reflection;

public static class Property
{
  public static PropertyInfo FromExpressionCached<T>(Func<Expression<Func<T, object>>> propertyExpression)
  {
    // check whether the delegate targets our cache holder
    var data = propertyExpression.Target as CachedData;
    if (data != null) return data.CachedValue;

    return FromImpl(propertyExpression); // otherwise, compute the PropertyInfo
  }

  private static PropertyInfo FromImpl<T>(Func<Expression<Func<T, object>>> propertyExpression)
  {
    // require a delegate with no captured context
    // so the compiler can cache it in a static field
    if (propertyExpression.Target != null)
      throw new ArgumentException("Delegate should not have any closures.");
    if (!propertyExpression.Method.IsStatic)
      throw new ArgumentException("Delegate should be static.");

    var body = propertyExpression().Body; // invoke the delegate

    // the object return type may introduce a boxing conversion
    if (body.NodeType == ExpressionType.Convert && body.Type == typeof(object))
    {
      body = ((UnaryExpression) body).Operand;
    }

    var memberExpr = body as MemberExpression;
    if (memberExpr == null)
      throw new ArgumentException("MemberExpression expected");

    if (memberExpr.Member.MemberType != MemberTypes.Property)
      throw new ArgumentException("Property member expected");

    var propInfo = (PropertyInfo) memberExpr.Member;

    // the delegate refers to a static method, so the compiler should
    // have cached it in a static field of the declaring type
    var declaringType = propertyExpression.Method.DeclaringType;
    foreach (var fieldInfo in declaringType.GetFields(BindingFlags.Static | BindingFlags.NonPublic))
    {
      // search the static fields for this delegate instance
      if (ReferenceEquals(fieldInfo.GetValue(null), propertyExpression))
      {
        // found it: create a holder for the PropertyInfo
        var cached = new CachedData { CachedValue = propInfo };
        // replace the cached delegate with one targeting the stub method
        var stub = new Func<Expression<Func<T, object>>>(cached.Stub<T>);
        fieldInfo.SetValue(null, stub);
        return propInfo;
      }
    }

    throw new InvalidOperationException("Delegate is not cached.");
  }

  // a closure-like object that holds the cached value
  private sealed class CachedData
  {
    public PropertyInfo CachedValue { get; set; }

    public Expression<Func<T, object>> Stub<T>()
    {
      throw new InvalidOperationException("Should never be called");
    }
  }
}
```

On the first call, we invoke the supplied delegate, compute the `PropertyInfo`, and replace the compiler-cached delegate with a stub whose target holds that value. The next call from the same site passes our stub instead of the original delegate. Retrieving the cached value then takes just one type test and a property access. Despite the amount of code and the initial use of reflection, this is much faster than constructing an expression tree on every call:

```c#
using System;
using System.Diagnostics;
using System.Threading;

static class Program
{
  private static void Main()
  {
    Thread.CurrentThread.Priority = ThreadPriority.Highest;
    const int count = 100000;

    var sw = Stopwatch.StartNew();
    for (var i = 0; i < count; i++)
    {
      var p = Property.Of((Stopwatch _) => _.Elapsed);
      GC.KeepAlive(p);
    }

    Console.WriteLine("expr: {0}", sw.Elapsed);
    sw.Reset();
    sw.Start();

    for (var i = 0; i < count; i++)
    {
      var p = Property.FromExpressionCached<Stopwatch>(() => _ => _.Elapsed);
      GC.KeepAlive(p);
    }

    Console.WriteLine("hack: {0}", sw.Elapsed);
  }
}
```

On a laptop with a Core i3 running at 2.533 GHz, I get the following typical results: a difference of almost three orders of magnitude.

```
expr: 00:00:01.0867601
hack: 00:00:00.0014079
```

Do not use this in production. It depends on compiler implementation details, overwrites compiler-generated static fields, and has unresolved concurrency issues. The code is an experiment intended to demonstrate the potential benefit of expression tree caching in C#.