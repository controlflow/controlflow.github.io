---
layout: post
title: "C# attribute-target-specifier"
date: 2010-11-04 18:51:04
author: Aleksandr Shvedov
tags: csharp attributes typevar
---
The C# grammar lists a limited set of attribute targets, which specify the language element to which an attribute applies:

> *attribute-section:*<br/>
>     [ *attribute-target-specifier<sub>opt</sub>  attribute-list* ]<br/>
>     [ *attribute-target-specifier<sub>opt</sub>  attribute-list ,* ]<br/>
> <br/>
> *attribute-target-specifier:*<br/>
>     *attribute-target :*<br/>
> <br/>
> *attribute-target:*<br/>
>     `field`<br/>
>     `event`<br/>
>     `method`<br/>
>     `param`<br/>
>     `property`<br/>
>     `return`<br/>
>     `type`

The C# 4.0 compiler is less restrictive than this grammar suggests. Consider the following code:

```c#
[someCrazyAttributeTargetLocation: Serializable]
class Foo;
```

It compiles without errors, but produces one warning:

> warning CS0658: ‘someCrazyAttributeTargetLocation’ is not a recognized attribute location. All attributes in this block will be ignored.

As a result, `typeof(Foo).IsSerializable == false` at runtime. However, [a post by Vladimir Reshetnikov on RSDN](http://rsdn.ru/forum/dotnet/4024505.aspx) points out another *attribute-target-specifier* that is absent from the grammar but accepted by the compiler without a warning:

```c#
[AttributeUsage(AttributeTargets.GenericParameter)]
sealed class FooAttribute : Attribute;

sealed class Bar<[typevar: Foo] T>;
```

The unlisted attribute target is `typevar`. It applies to generic type parameters. Using this target anywhere else, even after removing `[AttributeUsage]` from the attribute definition, produces warning *CS0658*.

The F# compiler is stricter: it rejects arbitrary attribute target names altogether.