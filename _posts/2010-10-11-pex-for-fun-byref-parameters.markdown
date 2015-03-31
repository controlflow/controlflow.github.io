---
layout: post
title: "Pex for fun + byref parameters"
date: 2010-10-11 15:58:01
categories: 1290985272
tags: pex ref parameter byref
---
Обнаружил, что Pex [не справился](http://www.pexforfun.com/default.aspx?language=CSharp&code=pADsvQdgHEmWJSYvbcp7f0r1StfgdKEIgGATJNiQQBDswYjN5pLsHWlHIymrKoHKZVZlXWYWQMztnbz33nvvvffee__997o7nU4n99%2f%2fP1xmZAFs9s5K2smeIYCqyB8%2ffnwfPyJW60lZTNNpmTVN_rKuLupskfziJE31i6bNWvpxWRWz9OX6Bz8o8606P0_LZZu_G6Xm1_s79AbeStN36WfpziH%2fek2%2f7sqvxXm6Rd%2fQ33fSdl5XV_kyv0pfXzdtvhgf1xfrRb5sT99N81VbVMutj86r6nf96A7e%2fSXJL%2fl%2fAgAA%2f%2f8%3d) с таким простым заданием:

{% highlight C# %}
public class Program
{
  public static void Puzzle(ref int x, ref int y)
  {
    x = 0;
    y = 1;
    if (x == 1) throw new System.ArgumentException("foo!");
  }
}

{% endhighlight %}

Да, надо быть готовым к тому, что несколько ref-параметров вполне могут ссылаться на одну и ту же переменную/поле =)