---
layout: post
title: "Memoizing functions with a PostSharp aspect"
date: 2010-12-19 14:29:00
author: Aleksandr Shvedov
tags: csharp postsharp aop memoize aspect
---
I recently tried [PostSharp](http://www.sharpcrafters.com/) 2.0 to explore its infrastructure, aspect APIs, and debugging experience. My first impression was positive: installation was straightforward, the Community Edition covered what I needed, and using it in a project required only a reference to `PostSharp.dll`.

I chose function memoization as an exercise. The [example](http://dpatrickcaldwell.blogspot.com/2009/02/memoizer-attribute-using-postsharp.html) I found online concatenated the string representations of all arguments into a dictionary key. I wanted an implementation that preserved argument types and left room for different caching strategies.

PostSharp aspects are classes derived from `System.Attribute`: ordinary attributes with additional behavior. PostSharp provides several base classes, including:

* `MethodInterceptionAspect` — intercepts method calls;
* `LocationInterceptionAspect` — intercepts access to properties and fields;
* `OnMethodBoundaryAspect` — runs code at method entry and exit;
* `OnExceptionAspect` — handles exceptions thrown by methods;
* `EventInterceptionAspect` — intercepts event subscriptions.

We need to intercept method calls, but we must also choose the aspect's lifetime. Aspects can be scoped to a type or to an instance. By default, an aspect derived from `MethodInterceptionAspect` is scoped to the type. Applied to an instance method, it would share one argument/result cache across all instances. That is usually incorrect: `this` is effectively another input to the method. Implementing `IInstanceScopedAspect` gives each object its own aspect instance and therefore its own cache:

```c#
/// <summary>
/// Memoize the method marked with this attribute.
/// Methods with ref or out parameters are not supported.
/// </summary>
[Serializable, AttributeUsage(AttributeTargets.Method)]
public sealed class MemoizeAttribute : MethodInterceptionAspect, IInstanceScopedAspect
{
    // Select the concurrent cache implementation.
    public bool IsThreadSafe { get; set; }
```

PostSharp aspects and their nested cache classes must be marked `[Serializable]`. The `IsThreadSafe` property becomes a named attribute argument, allowing callers to request the concurrent cache implementation. Supporting `ref` and `out` parameters would make the example substantially more complex, so they are outside its scope.

We also need to control where the attribute can be used. This implementation requires a return value and at least one parameter. PostSharp provides the virtual `CompileTimeValidate()` method for validating aspect usage during compilation. An override can also return `false` to skip applying the aspect without reporting an error:

```c#
/// <summary>
/// Validate usage of the memoization aspect.
/// </summary>
public override bool CompileTimeValidate(MethodBase method)
{
  var mi = (MethodInfo) method;
  if (mi.ReturnType == typeof(void))
  {
    throw new InvalidOperationException(
      "The aspect requires a method that returns a value.");
  }

  var parameters = mi.GetParameters();
  if (parameters.Length == 0)
  {
    throw new InvalidOperationException(
      "The aspect requires a method with at least one parameter.");
  }

  foreach (var parameter in parameters)
  {
    if (parameter.IsIn || parameter.IsOut)
    {
      throw new InvalidOperationException(
        "The aspect does not support methods with ref or out parameters.");
    }
  }

  return true;
}
```

One inconvenience is that I could not navigate directly from these PostSharp errors in Visual Studio to the invalid attribute usage. There appeared to be an API for better diagnostics, but I had not worked out how to use it.

Now we can design the cache. PostSharp exposes arguments and return values through the weakly typed `MethodInterceptionArgs` API, while the cache should retain their concrete types. We can start with this abstraction:

```c#
[Serializable]
private abstract class MemoCache
{
  public abstract bool TryResolve(object arg, out object result);
  public abstract void AppendItem(Arguments arg, int index, object result);
}
```

The interface uses `object` for lookups and insertions, but `TryResolve` accepts only one argument. To handle methods with several parameters, the cache keyed by the first argument can contain caches keyed by the second, and so on. This avoids building and hashing a composite key for every lookup, permits an early exit when an argument is missing, and distributes concurrent access across separate caches. The next class introduces generic key and value types:

```c#
[Serializable]
private abstract class MemoCache<T, TResult> : MemoCache
{
  private static readonly Func<MemoCache> NestedCacheFactory;

  static MemoCache()
  {
    // check whether values in this cache
    // are themselves nested caches
    if (typeof(TResult).IsSubclassOf(typeof(MemoCache)))
    {
      NestedCacheFactory = GetCacheFactory(typeof(TResult));
    }
  }

  protected abstract void AppendImpl(T arg, TResult result);

  public sealed override void AppendItem(Arguments arg, int index, object result)
  {
    if (NestedCacheFactory == null)
    {
      // store the result directly
      AppendImpl((T) arg[index], (TResult) result);
    }
    else
    {
      // create a nested cache
      var nested = NestedCacheFactory();
      AppendImpl( // store it in the current cache
        (T) arg[index],
        (TResult) (object) nested);

      // cache the next argument
      nested.AppendItem(arg, index + 1, result);
    }
  }
}
```

This class supplies the insertion logic. Its static constructor checks whether the cached values are themselves caches. If so, `GetCacheFactory()`, defined below, supplies a delegate that creates them. Insertion then creates a nested cache, stores the pair (*current argument*, *nested cache*), and passes the remaining arguments and result to that cache. At the innermost level, it simply stores the pair (*argument*, *return value*).

For example, a method with the signature `int F(int, string, decimal)` needs a cache of this shape:

```c#
SomeCache<int, SomeCache<string, SomeCache<decimal, int>>>
```

Here, `SomeCache<,>` is a subclass of `MemoCache<,>` that defines how entries are stored. The outer cache maps the first `int` argument to a second-level cache. That cache maps the `string` argument to a third-level cache, which maps the `decimal` argument to the method's `int` result.

A straightforward implementation uses `Dictionary<,>`:

```c#
/// <summary>
/// Cache backed by an ordinary dictionary.
/// </summary>
[Serializable]
private sealed class DictionaryCache<T, TResult> : MemoCache<T, TResult>
{
  private readonly Dictionary<T, TResult> cache = new Dictionary<T, TResult>();

  public static MemoCache CreateInstance()
  {
    return new DictionaryCache<T, TResult>();
  }

  public override bool TryResolve(object arg, out object result)
  {
    TResult value;
    if (cache.TryGetValue((T) arg, out value))
    {
      result = value;
      return true;
    }
    else
    {
      result = null;
      return false;
    }
  }

  protected override void AppendImpl(T arg, TResult result)
  {
    cache.Add(arg, result);
  }
}
```

The static `CreateInstance()` method supplies the factory delegate used to create caches. `GetCacheFactory()` finds that method and creates the delegate:

```c#
/// <summary>
/// Return a factory for instances of the given cache type.
/// </summary>
private static Func<MemoCache> GetCacheFactory(Type cacheType)
{
  // find "public static MemoCache CreateInstance()"
  var methodInfo = cacheType.GetMethod(
    "CreateInstance", BindingFlags.Static | BindingFlags.Public);

  // create a delegate for subsequent factory calls
  return (Func<MemoCache>)
    Delegate.CreateDelegate(typeof(Func<MemoCache>), methodInfo);
}
```

Each concrete cache type needs to provide this factory method. Here is another implementation using `ConcurrentDictionary<,>` from .NET 4.0:

```c#
/// <summary>
/// Cache backed by a concurrent dictionary.
/// </summary>
[Serializable]
private sealed class ConcurrentCache<T, TResult> : MemoCache<T, TResult>
{
  private readonly ConcurrentDictionary<T, TResult> cache = new ConcurrentDictionary<T, TResult>();

  public static MemoCache CreateInstance()
  {
    return new ConcurrentCache<T, TResult>();
  }

  public override bool TryResolve(object arg, out object result)
  {
    TResult value;
    if (cache.TryGetValue((T) arg, out value))
    {
      result = value;
      return true;
    }
    else
    {
      result = null;
      return false;
    }
  }

  protected override void AppendImpl(T arg, TResult result)
  {
    cache.AddOrUpdate(arg, result, (_, x) => x);
  }
}
```

Next, we need to construct the root cache's `System.Type` from the method being memoized:

```c#
/// <summary>
/// Construct the cache type from the method parameter types
/// and the requested concurrency setting.
/// </summary>
private Type GetRootCacheType(MethodInfo method)
{
  Debug.Assert(method != null);

  var parameters = method.GetParameters();
  var resultType = method.ReturnType;

  // choose the cache implementation
  var cacheType = IsThreadSafe ? typeof(ConcurrentCache<,>) : typeof(DictionaryCache<,>);

  // visit parameters in reverse order
  for (int i = parameters.Length - 1; i >= 0; i--)
  {
    // build "Cache<T1, Cache<T2, Cache<T3, TResult>>>",
    // where T1, T2, and T3 are the method parameter types
    resultType = cacheType.MakeGenericType(parameters[i].ParameterType, resultType);
  }

  return resultType;
}
```

This method selects the dictionary implementation according to the aspect's `IsThreadSafe` property. The same construction could be extended to other cache types, such as caches with capacity limits or expiring entries.

We can now add the root cache field and the method-call interceptor:

```c#
private MemoCache cacheRoot;

/// <summary>
/// Intercept a call to the memoized method.
/// </summary>
public override void OnInvoke(MethodInterceptionArgs args)
{
  MemoCache argCache = this.cacheRoot;
  Arguments arguments = args.Arguments;
  object result = null;
  int index = 0;

  LookupArg: // look up arguments in successive caches
  if (argCache.TryResolve(arguments[index++], out result))
  {
    // before the last argument, the result is another cache
    if (index < arguments.Count)
    {
        argCache = (MemoCache) result;
        goto LookupArg; // continue with the next argument
    }

    args.ReturnValue = result;
  }
  else // on a miss, invoke the method and cache its result
  {
    args.Proceed();
    argCache.AppendItem(arguments, index - 1, args.ReturnValue);
  }
}
```

The `goto` keeps the lookup path explicit: each successful lookup either yields the result or advances to the next cache. On a miss, `argCache` already refers to the cache where the missing argument belongs, so insertion does not need to traverse the preceding levels again.

The aspect's runtime initialization method inspects the target method and prepares a factory for root caches:

```c#
private static Func<MemoCache> RootCacheFactory;

/// <summary>
/// Initialize the aspect for the target method.
/// Create the root cache here for static methods.
/// </summary>
public override void RuntimeInitialize(MethodBase method)
{
  var type = GetRootCacheType((MethodInfo) method);
  RootCacheFactory = GetCacheFactory(type);

  if (method.IsStatic)
    this.cacheRoot = RootCacheFactory();

  base.RuntimeInitialize(method);
}
```

This method runs once for each method to which the aspect is applied. For a static method, it creates the root cache immediately. For instance methods, PostSharp uses the `IInstanceScopedAspect` implementation:

```c#
/// <summary>
/// Create a per-object aspect from the constructor of the type
/// whose instance method is being memoized.
/// </summary>
public object CreateInstance(AdviceArgs adviceArgs)
{
  return new MemoizeAttribute
  {
      IsThreadSafe = this.IsThreadSafe
  };
}

/// <summary>
/// Initialize the per-object aspect.
/// </summary>
public void RuntimeInitializeInstance()
{
  this.cacheRoot = RootCacheFactory();
}
```

`CreateInstance()` creates the per-object aspect and copies its configuration from the type-scoped aspect. `RuntimeInitializeInstance()` then initializes that aspect's root cache.

We can exercise both variants with factorial methods:

```c#
class Foo
{
  [Memoize]
  private static int StaticFact(int x)
  {
      Console.WriteLine("=> StaticFact({0}) call", x);

    if (x == 0) return 1;
    return x * StaticFact(x - 1);
  }

  [Memoize(IsThreadSafe=true)]
  private int InstanceFact(int x)
  {
    Console.WriteLine("=> InstanceFact({0}) call", x);

    return Enumerable
      .Range(1, x)
      .Aggregate(1, (a, b) => a * b);
  }

  private static void Main()
  {
    Action<string, object> wl = Console.WriteLine;

    wl("StaticFact(2) = {0}", StaticFact(2));
    wl("StaticFact(2) = {0}", StaticFact(2));
    wl("StaticFact(7) = {0}", StaticFact(7));
    wl("StaticFact(7) = {0}", StaticFact(7));

    Console.WriteLine();

    var a = new Foo();
    var b = new Foo();

    wl("a.InstanceFact(7) = {0}", a.InstanceFact(7));
    wl("a.InstanceFact(7) = {0}", a.InstanceFact(7));

    wl("b.InstanceFact(7) = {0}", b.InstanceFact(7));
    wl("b.InstanceFact(7) = {0}", b.InstanceFact(7));
  }
}
```

The static method is recursive, while the instance method computes its result iteratively. Running the example produces:

    => StaticFact(2) call
    => StaticFact(1) call
    => StaticFact(0) call
    StaticFact(2) = 2
    StaticFact(2) = 2
    => StaticFact(7) call
    => StaticFact(6) call
    => StaticFact(5) call
    => StaticFact(4) call
    => StaticFact(3) call
    StaticFact(7) = 5040
    StaticFact(7) = 5040

    => InstanceFact(7) call
    a.InstanceFact(7) = 5040
    a.InstanceFact(7) = 5040
    => InstanceFact(7) call
    b.InstanceFact(7) = 5040
    b.InstanceFact(7) = 5040

Repeated calls use the cached result, and each `Foo` instance has its own cache. Exceptions thrown by the memoized method are not cached: they propagate to the caller, and a later call with the same arguments attempts the computation again.

The complete example is available in [this gist](https://gist.github.com/controlflow/8a40704e3b623d302765b2b3c05c8a8f).