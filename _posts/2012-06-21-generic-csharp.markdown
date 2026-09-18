---
layout: post
title: "A look back at 2001: the Generic C# specification"
date: 2012-06-21 11:12:00
author: Aleksandr Shvedov
tags: csharp fsharp generics types typesystems clr
---
Don Syme recently [published a piece of Microsoft Research history on his blog](https://dsyme.net/2012/06/19/some-history-2001-gc-research-project-draft-from-the-msr-cambridge-team/): a draft specification for the research language GC# (*Generic C#*), dated December 12, 2001. It extended the C# 1.0 language with parametric polymorphism. A [local copy of the specification (PDF)]({{ site.baseurl }}/assets/docs/generic-csharp-specification-2001-12-12.pdf) is preserved here as well.

The draft differs substantially from C# 2.0, which brought reified generics into production. Comparing them offers a useful view of the design decisions that shaped the language. Here are the details that caught my attention.

* GC# proposed allowing `using` aliases to declare their own type parameters:

```c#
using IntDict<T> = System.Collections.Generic.Dictionary<int, T>;
```

This was never implemented in GC# and did not make it into C# 2.0, although F# has a very similar feature in its type abbreviations. It would be a small but useful addition, even within the limited role of `using` aliases in C#.

* Generic types could not be overloaded by their number of type parameters. The metadata naming scheme gave generic types a fixed suffix rather than encoding their arity, so these declarations conflicted:

```c#
class C { }
class C<T> { }
class C<T, U> { }
```

GC# did not impose the same restriction on generic method overloads. C# 2.0 accepts the type declarations above because their metadata names are `C`, ``C`1``, and ``C`2``. Removing the restriction was a good decision: types with the same name and different arities can be useful, particularly in framework APIs.

* The expression for the default value of a type parameter `T` used a different syntax: `default<T>`.

* Besides constructed types and type parameters, GC# proposed allowing `void` as a special type argument. This was not implemented because GCLR (*Generic CLR*, the experimental runtime with reified generics) retained the special treatment of `void` in IL. One suggested implementation was to have the compiler transparently replace `void` type arguments with an empty value type, `System.Empty`, playing a role similar to F#'s `unit`.

A `void` type argument would allow an override such as this:

```c#
class C<T>
{
  public virtual T M() { … }
}

class D : C<void>
{
  public override void M() { … }
}
```

The proposed translation looked roughly like the following. This is illustrative pseudocode rather than valid C#: among other things, the generated override changes accessibility.

```c#
class C<T>
{
  public virtual T M() { … }
}

class D : C<System.Empty>
{
  private sealed override System.Empty M()
  {
    this.M();
    return new System.Empty();
  }
  public new virtual void M() { … }
}
```

Similar adaptations were proposed when converting a method group returning `void` to a constructed generic delegate type whose return type became `void` after substitution. The compiler would generate wrapper methods, sometimes involving closures.

As I understand the proposal, parameters whose types became `void` after substitution would disappear from the source-level parameter list. The compiler would supply `System.Empty` values for the corresponding hidden parameters.

Why go to this trouble? Treating `void` as a unit type could remove the need for separate `Action<T>` and `Func<T, TResult>` delegate families: `Action<T>` could be expressed as `Func<T, void>`. This would eliminate many paired overloads in APIs that use both families. Likewise, separate `Task` and `Task<T>` types might not be needed. With the proposed compiler translation, however, creating these delegates would incur some wrapper overhead.

If the CLR had represented `void` as an ordinary empty value type from the beginning, with the usual rules for values on the IL evaluation stack, the feature could have fit naturally without those wrappers. Adding generics required substantial IL changes, but the treatment of `void` remained unchanged, and support for `void` type arguments was dropped.

* GC# proposed an interface-uniqueness restriction that would prevent a class from implementing the same generic interface with different type arguments. It was never implemented, and C# 2.0 has no such blanket restriction:

```c#
interface I<T> { }
class C : I<string>, I<object> { }

```

* Static fields in GC# could not refer to type parameters of their declaring class. These declarations were rejected:

```c#
class C<T>
{
  private static T Field;
  private static List<T> Xs;
}

```

The reason was straightforward: GCLR shared static fields among all constructed types of a generic class. Java has a similar restriction, though there it follows from type erasure and the absence of runtime generic instantiations. By C# 2.0, the CLR allocated separate static fields for each closed constructed type.

I find this behavior useful and consistent. It can still surprise developers who are unaware of it and unintentionally initialize identical static data separately for many constructed types.

By default, ReSharper warns about static fields in generic types when the field's type does not mention any type parameters. I am not especially fond of that heuristic, but determining whether the field's value depends on a type parameter is not generally possible.

* A similar restriction applied to static methods, properties, and events. The following was not allowed:

```c#
class C<T>
{
  public static void M(C<T> c) { }
}
```

The reason is less clear to me. GCLR could already pass type arguments to static generic methods, which the GC# specification recommended as a workaround. Perhaps the restriction was related to shared static data, or to a case where the runtime could not recover the class's type arguments. Instance methods did not have this problem: they could obtain the reified type arguments through the object's runtime type information.

The production CLR can supply generic context to shared static-method code through a hidden argument, and generate specialized code for value-type instantiations. The restriction disappeared, leaving the more consistent behavior available in C# 2.0.

The GC# restriction also interfered with operators on generic types, since operators are static methods. The proposed workaround was to allow generic operators. Their type arguments would have to be inferred because operator syntax provides nowhere to specify them explicitly. This feature disappeared along with the original restriction:

```c#
public class C<T>
{
  public static C<T> operator+ <T> (C<T> lhs, C<T> rhs) { … }
}

```

* In GC#, an enclosing class's type parameters did not implicitly become type parameters of its nested classes:

```c#
class C<T>
{
  private class N    { /* Cannot refer to the outer T. */ }
  private class N<T> { /* Can declare its own T. */ }
}
```

In C# 2.0, nested types carry the type parameters of their enclosing generic types as well as any they declare themselves. The reflected names in this example are ``C`1``, ``C`1+N``, and ``C`1+N`1``; the nested types have one and two generic parameters respectively. This avoids repeating the enclosing parameters, but introduces scope and shadowing rules: the inner `T` in `N<T>` hides the outer `T`. It also means that a nested type inside a generic class cannot be completely independent of the outer type's instantiation. Despite that tradeoff, I prefer the implicit approach, even though it makes IDE support more involved.

* One proposal took me a while to notice: delegates could have two sets of type parameters. This was never implemented:

```c#
delegate void Foo <T><U>(T t, U u);
```

The first set, called *delegate-create-type-parameters*, corresponds to ordinary generic delegate type parameters in C#.

The second set, *delegate-invoke-type-parameters*, belongs to the `Invoke` method itself. These type arguments would be supplied when invoking the delegate, rather than when creating it. Conceptually, such a delegate would behave like this class:

```c#
abstract class Printer<T>
{
  public abstract void Invoke<U>(T t, U u);
}
```

This could express *rank-2 polymorphism*: a method could accept a delegate and invoke it with several different types. It could also provide a basis for generic anonymous methods or lambdas. The aim was to make a delegate as expressive as an abstract generic method on a generic class. For example:

```c#
delegate void Printer<T><U>(T t, U u);

class Program
{
  public void PrintGeneric<U>(int padding, U u) { … }
  public void PrintValues(Printer<int> printer)
  {
    printer(100, 123);
    printer(100, "abc");
    printer(100, true);
  }

  public void Run()
  {
    PrintValues(PrintGeneric);
  }
}
```

My guess is that the runtime work and the complexity of method-group conversion rules helped keep this proposal from reaching the final language.

* GC# had no `struct`, `class`, or `new()` constraints. It also prohibited subtype constraints referring to another type parameter. Note the proposed constraint syntax:

```c#
class C<T, U | T : U> { … } // Invalid in GC#.
```

I see some of these constraints as compromises arising from the C#/CLR type system and the implementation of reified generics. The reflection-based implementation of `new()` was a particular frustration. I wonder whether a different design could have avoided separate `class` and `struct` constraints. Constraints involving another type parameter, though uncommon, are an interesting capability.

* GC# also proposed inferring a constructed type's type arguments from constructor arguments, including delegate constructors. This was not implemented. It could have removed explicit type arguments from calls such as these:

```c#
private int F(int x) { … }
private int G(int x) { … }
var f = new Func(x => F(x) + G(y)); // Func<int, int>
var xs = new List(someIntEnumerable); // List<int>

```

This seems useful and reasonably straightforward to implement, but it is still absent from C# at the time of writing. One complication is overload resolution across constructors of entirely different types: consider what would happen if both `List` and `List<T>` had constructors applicable to the final call above.

The specification contains more small design choices worth exploring. Even the proposals that were dropped help explain why generics in C# and the CLR took their eventual form.