---
layout: post
title: "First-class call sites?"
date: 2012-02-27 12:05:00
author: Aleksandr Shvedov
tags: csharp callsite dynamic caching
---
Let me start with the background. A few days ago, while revisiting C# 4.0's `dynamic`, I wondered what we could do if a language let a function access *a reified representation of its call site*: a value identifying the location in the calling code. A function `F()` could then distinguish calls from different places. At first, this sounds like a terrible idea. Who wants to debug a function whose behavior can change depending on where it is called?

There is, however, one fairly narrow area where this could be useful: *caching*. Caching is essential to the product I work on, and it appears throughout the code. I have noticed that many cache lookups use arguments that either fall within a range specific to that call site or are simply constant:

```c#
public IDeclaredType ResourceKey
{
  get { return GetType("System.Windows.ResourceKey"); }
}

public IDeclaredType EventSetter
{
  get { return GetType("System.Windows.EventSetter"); }
}

public IDeclaredType Trigger
{
  get { return GetType("System.Windows.Trigger"); }
}
```

Here, `GetType()` looks up the fully qualified type name in a dictionary and searches the assemblies if the lookup misses. Between invalidations of the entire cache, we can treat `GetType()` as effectively pure. For these constant-argument calls, the dictionary lookup is not really necessary: each call site could cache its result in a separate field, reducing the lookup to a single `if`.

The problem is that my code currently contains 121 such calls, with constant arguments in 90% of cases. Adding a field and an explicit check, under a `lock` as well, for every call site is hardly appealing or reasonable. The entire cache is also invalidated very frequently: practically every keystroke outside a method body can introduce or remove a type. Even with this invalidation rate, the cache has a 99.993% hit rate, so it is still extremely useful. Turning invalidation into the task of clearing a huge collection of individual fields would be unacceptable.

If `GetType()` could receive an object identifying its call site, we could build a much *more granular cache*. C# already uses similar techniques, which I will come back to shortly. Imagine a language extension called *first-class call sites*, where a call site is represented as a value. It could make this kind of caching easier to express. Here is a factorial example using hypothetical syntax:

```c#
// declaration
private static int Fact(int x, Dictionary<int, int> cache = callsite)
{
  int result;
  if (cache.TryGetValue(x, out result)) return result;

  result = (x == 0) ? 1 : x * Fact(x - 1, cache);
  cache[x] = result;
  return result;
}

// usage
Fact(6);

```

The idea is fairly straightforward: teach the compiler to generate hidden fields for each call site and automatically pass their values to optional parameters marked with an appropriate annotation. For now, I am leaving aside the question of how to invalidate these distributed caches.

C# 4.0's `dynamic` uses a similar technique. An expression such as `d.Foo`, where `d` is `dynamic`, is not simply translated into a call to something like `GetMemberDynamic(object target, string name)`. The compiler does considerably more work. Each dynamic operation gets a call-site object, created once and stored in a static field. Along with the binding infrastructure, this object holds an ordinary .NET delegate that is invoked whenever the operation executes.

On the first execution, the dynamic binding infrastructure applies the C# binding rules at runtime to resolve the operation. If successful, it compiles a delegate that performs the operation. The generated code also checks whether that delegate can be reused on subsequent executions. For example, if `foo.Bar` initially resolves to the `Bar` property on a `ConcreteFoo` instance, the delegate can be reused when `foo` is again a `ConcreteFoo`.

Otherwise, the operation must be resolved again, and the infrastructure can compile a replacement delegate. The implementation keeps the ten most recent delegates in the call-site object, since they may be useful again.

After a little warm-up, most dynamic operations therefore become calls to ordinary delegates with one or two `if` checks. This is much more efficient than the initial binding and compilation, and demonstrates the value of caching at the call site in scenarios like this. It is closely related to *polymorphic inline caching*, where executable code is updated at runtime to cache dispatch decisions. Similar techniques are used by JavaScript engines and by the CLR JIT for interface calls.