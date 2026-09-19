---
layout: post
title: "The mighty Delegate.CreateDelegate"
date: 2011-01-17 16:19:00
author: Aleksandr Shvedov
tags: csharp delegate createdelegate dynamicmethod begininvoke ref valuetype
---
The [`System.Delegate.CreateDelegate`](https://learn.microsoft.com/en-us/dotnet/api/system.delegate.createdelegate) method has been available since the earliest versions of the .NET Framework. It creates a delegate dynamically from a delegate type, supplied as a `System.Type`, and a method, identified by its name or a `System.Reflection.MethodInfo`. What makes it interesting is the variety of ways it can bind a method to a delegate signature.

Consider the following class and struct:

```c#
class FooClass
{
  public static void StaticBar(object x) { }
  public string InstanceBar(int x) { return "abc"; }
}

struct FooStruct
{
  public void InstanceBoo(int x) { }
}
```

Here are the kinds of delegates we can create:

* **A delegate for a static method**

  In C#, we can create an `Action<object>` delegate from `FooClass.StaticBar` using a method group:

  ```c#
  Action<object> staticBar = FooClass.StaticBar;
  ```

  The equivalent call to `Delegate.CreateDelegate` is:

  ```c#
  var staticBar = (Action<object>) Delegate.CreateDelegate(
    type: typeof(Action<object>),
    method: typeof(FooClass).GetMethod("StaticBar"));
  ```

* **A delegate for an instance method**

  C# also supports binding a delegate to a particular object:

  ```c#
  Func<int, string> instanceBar1 = new FooClass().InstanceBar;
  ```

  With `Delegate.CreateDelegate`, the additional `firstArgument` parameter supplies the object on which the instance method will be invoked:

  ```c#
  var instanceBar = (Func<int, string>) Delegate.CreateDelegate(
    type: typeof(Func<int, string>),
    method: typeof(FooClass).GetMethod("InstanceBar"),
    firstArgument: new FooClass()); /* <== */
  ```

  Instance methods on value types are supported too. In this case, the struct is boxed:

  ```c#
  var instanceBoo = (Action<int>) Delegate.CreateDelegate(
    type: typeof(Action<int>),
    method: typeof(FooStruct).GetMethod("InstanceBoo"),
    firstArgument: new FooStruct()); /* <== */
  ```

* **Contravariant parameter types**

  C# supports contravariance in parameter types when converting a *method group* to a delegate. For example, a method with this signature:

  ```c#
  private void Foo(object sender, EventArgs e)
  ```

  can handle an event whose delegate has this signature:

  ```c#
  void PropertyChangedEventHandler(object sender, PropertyChangedEventArgs e)
  ```

  This works because `PropertyChangedEventArgs` derives from `EventArgs`. Likewise, the following conversion is valid because `string` derives from `object`:

  ```c#
  Action<string> contravariantParameterType = FooClass.StaticBar;
  ```

  `Delegate.CreateDelegate` supports the same parameter contravariance:

  ```c#
  var contravariantParameterType = (Action<string>) Delegate.CreateDelegate(
    type: typeof(Action<string>),
    method: typeof(FooClass).GetMethod("StaticBar"));
  ```

* **Covariant return types**

  C# also supports covariance in the return type:

  ```c#
  Func<int, object> covariantReturnType = new FooClass().InstanceBar;
  ```

  The same conversion works with `Delegate.CreateDelegate`:

  ```c#
  var covariantReturnType = (Func<int, object>) Delegate.CreateDelegate(
    type: typeof(Func<int, object /* <== */>),
    method: typeof(FooClass).GetMethod("InstanceBar"),
    firstArgument: new FooClass());
  ```

* **An open instance delegate for a reference type**

  An open instance delegate exposes the target object as its first argument. C# cannot create one directly through a method group conversion. With `Delegate.CreateDelegate`, we omit `firstArgument` and choose a delegate type whose first parameter is the reference type declaring the method. The instance method can then be called through the delegate as though it were static:

  ```c#
  var instanceBarAsStatic = (Func<FooClass, int, string>) Delegate.CreateDelegate(
    type: typeof(Func<FooClass /* <== */, int, string>),
    method: typeof(FooClass).GetMethod("InstanceBar"));
  ```

  The same delegate can be invoked on different objects:

  ```c#
  var foo1 = new FooClass();
  var foo2 = new FooClass();

  instanceBarAsStatic(foo1, 1);
  instanceBarAsStatic(foo2, 2);
  instanceBarAsStatic(null, 3); // null reference exception?
  ```

  There is a subtle difference from an ordinary C# instance call: the delegate invocation does not automatically check whether the target object (`this`) is `null`. The third call therefore succeeds for this method, which does not access any instance state:

  ![]({{ site.baseurl }}/images/delegate-create.png)

  Do not rely on this form of invocation to reject a `null` target.

* **A static delegate with a bound first argument**

  We can also bind the first argument of a static method. Supply `firstArgument` when creating the delegate, and omit the corresponding parameter from the delegate type:

  ```c#
  var staticBarWithFixedArg = (Action) Delegate.CreateDelegate(
    type: typeof(Action),
    method: typeof(FooClass).GetMethod("StaticBar"),
    firstArgument: new object()); /* <== */
  ```

  The delegate retains the `new object()` instance and supplies it as the first argument on every call. For this form of binding, the method's first parameter must be a reference type. This is partial application: one argument is fixed when the delegate is created.

* **An open instance delegate for a value type**

  I discovered this possibility while thinking about how instance methods on C# structs work. For a struct instance method, `this` behaves like a `ref` parameter; in a struct constructor, it behaves like an `out` parameter. It can even be assigned to. That suggests defining a delegate whose first parameter is a reference to the struct. The standard `Action` and `Func` delegate types do not support `ref` or `out` parameters, so we need our own type:

  ```c#
  delegate void FooStructBooRef(ref FooStruct foo, int x);
  ```

  We can then create the delegate without supplying `firstArgument`:

  ```c#
  var instanceBooAsStaticWithRef = (FooStructBooRef) Delegate.CreateDelegate(
    type: typeof(FooStructBooRef /* <== */),
    method: typeof(FooStruct).GetMethod("InstanceBoo"));
  ```

  This works, and lets us pass a different struct variable on each call:

  ```c#
  var foo1 = new FooStruct();
  var foo2 = new FooStruct();

  instanceBooAsStaticWithRef(ref foo1, 1);
  instanceBooAsStaticWithRef(ref foo2, 2);
  ```

  The first parameter can also be declared as `out`. At the CLR level, both `ref` and `out` are represented as by-reference parameters; the distinction is recorded in metadata and enforced by the C# compiler. However, methods such as `GetHashCode`, `Equals`, and `ToString` that the struct inherits rather than overrides still require boxing, so they cannot be bound in this way.