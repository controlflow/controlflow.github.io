---
layout: post
title: "C# delegate instances caching (part 1)"
date: 2010-10-15 01:25:47
author: Aleksandr Shvedov
tags: csharp delegate cache csc
---
I'd like to clarify when the C# compiler caches delegate instances.

Although invoking a delegate is roughly as fast as calling a method through an interface, *creating delegate instances* has a cost. In practice, that cost is usually only noticeable in performance-critical code and is rarely a concern in ordinary application development. Several relevant references were recently collected in [this RSDN discussion](http://rsdn.ru/forum/dotnet/3995281.flat.aspx).

The interesting part is the compiler's behavior and the code it generates. Consider this method containing a lambda expression:

```c#
private static IEnumerable<Person> FilterDevelopers(this IEnumerable<Person> source)
{
  return source.Where(x => x.IsDeveloper);
}
```

The syntax is familiar enough that it is easy to overlook the delegate instance involved. Making the delegate construction explicit gives:

```c#
private static IEnumerable<Person> FilterDevelopers(this IEnumerable<Person> source)
{
  return source.Where(new Func<Person, bool>(x => x.IsDeveloper));
}
```

In this example, the lambda does not capture any local variables or require access to `this`, so the compiler can turn it into an ordinary static method. There is therefore no need to allocate a new delegate on every call: delegates are immutable, and instances referring to the same static method are equivalent in behavior. The C# compiler takes advantage of this by caching the delegate in a static field. The generated code is approximately equivalent to the following:

```c#
[CompilerGenerated]
private static Func<Person, bool> CS9_CachedAnonymousMethodDelegate1;

private static IEnumerable<Person> FilterDevelopers(this IEnumerable<Person> source)
{
  return source.Where(
    CS9_CachedAnonymousMethodDelegate1 != null
      ? CS9_CachedAnonymousMethodDelegate1
      : (CS9_CachedAnonymousMethodDelegate1 =
          new Func<Person, bool>(x => x.IsDeveloper)));
}
```

This optimization applies to the non-capturing lambda shown here. It should not be generalized to all delegates referring to static methods: the C# compiler at the time of writing does not apply the same caching to ordinary method group conversions.

For a long time, I assumed that capturing any state would make caching impossible, since delegates created from lambdas or anonymous methods with different captured contexts are not interchangeable. It turns out that static methods are not the only case where caching is possible. I'll cover the other cases in later posts.

Delegate caching is strictly a compiler implementation detail. Program correctness must not depend on whether the compiler reuses a delegate instance, or on reference equality between delegates produced by repeated evaluations of the same expression.