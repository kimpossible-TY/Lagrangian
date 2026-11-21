# Native Reader runtime third-party notices

This private package preserves complete, unmodified registry packages, including source headers, font bytes and package license files. No lifecycle scripts run.

## Font upstream evidence

The 4.1.3 font npm archive omits LICENSE. Its published repository https://github.com/mathjax/MathJax-fonts and registry gitHead b3b77f655ed2d9009078301626e27b56dcfa90d9 returned HTTP 404 on 2026-11-17; these are not claimed as accessible evidence. Instead the SRI-authenticated **same-version** archive provides authoritative embedded font name-table notices and def/mathjax-newcm.ts:757. Apache-2.0 is the publisher declaration for the package wrapper, not a replacement for the embedded GUST font license. Standard Apache terms below are the unmodified LICENSE from @mathjax/src@4.1.3. All 105 original WOFF2 files remain intact.

Publisher addCopyright: `Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)`

Exact distinct WOFF2 name-table records (IDs 0/7/8/9/11/13/14; blank records omitted):

```text
(C) 2019-2021 Antonis Tsolomitis. 
This work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.
```

```text
Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)
Original copyright:
(C) 2019-2021 Antonis Tsolomitis. 
This work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.
```

```text
Please refer to the Copyright section for the font trademark attribution notices.
```

Per-file evidence (original bytes bind the embedded notices):

| WOFF2 | SHA-256 |
| --- | --- |
| mjx-ncm-ab.woff2 | 9813052b6bca662c7d7242e35e6b754de3edb6c469dc4c3af747a6b1d7de9962 |
| mjx-ncm-abi.woff2 | 544e713025065edf43e9b34b671bc47203d0879c73cccbaa000093ff07ae09da |
| mjx-ncm-ai.woff2 | ba7e5230b13bc7744e8b51f3cff12d43c4590b18122b4acd6b9bd03b9588d9b0 |
| mjx-ncm-ar.woff2 | 9e942b15ecbf57c84324aa27fdfbea5679de4bee0e1a578eb209153c60d8ad79 |
| mjx-ncm-arl.woff2 | ac5a25c0ab7082074f811aecf807cb16dc087879e3d58b5e2893eae0d6f1c449 |
| mjx-ncm-b-a.woff2 | 036467b277fb41f43d7a37b1190bb8c9069ff9896ffad8a3ea373fc3d4dba88a |
| mjx-ncm-b.woff2 | ea04057759e00963656c9cb63070acdfa20a6ebf441b63a004032fba63c01aef |
| mjx-ncm-bi.woff2 | 925f5064cbe2c9236c59821cb3ec9a411ee46ec32eaaee0fc1c5fd855fe9d098 |
| mjx-ncm-br.woff2 | 5276058e417131564b8e122e79564a5357bcfbe52ec99f381323f510bdab3e6c |
| mjx-ncm-brd.woff2 | dd74ff0393fc3662d30626a464c2a49e244b8c4407304fa048be097525882bfa |
| mjx-ncm-brk.woff2 | 4ba8ef6cf75997b0f62b21fac1633612469d6864026dc431a2f98565f4f86666 |
| mjx-ncm-c.woff2 | bfe4cd45950bd79704ad58fa97edb3d716c7d14a8a493e41ae3f537c43ada90d |
| mjx-ncm-cb.woff2 | 68ebec1310a6cbb92b4a968ea63e89353b06e3d06423e6073fd7e7aa0d528605 |
| mjx-ncm-ch.woff2 | 22cf130d6ce128ec6b97e66c256b36a29e1732c85fa8c972e6b9829b88e881f1 |
| mjx-ncm-chb.woff2 | 5cf157d3e5ac9147a5a965d8faa6b887e11a1e9cc6138b850b722a18cb4d90e5 |
| mjx-ncm-chbi.woff2 | f8495cf659299b1d7478b0b23f6e28b829ea6e690e2b511e2f83b7fbcb316cb7 |
| mjx-ncm-chi.woff2 | e10555212099fcfa9185103b7ac220e772ed6648ec1bb0cd22b5f2c40f8278aa |
| mjx-ncm-cy.woff2 | de6ce6188dfd327a493068d627914e3b32ddcec311e70b34f50b010da9980b14 |
| mjx-ncm-cyb.woff2 | eea8c28d0f92014ee12419acaaf419b054eaedbf487b42aa95433c06c2fd2670 |
| mjx-ncm-cybi.woff2 | d2c8c1b3858fcd6987615b7fc49a2e17c999d7b91467ec9399d6cf83370282cf |
| mjx-ncm-cyi.woff2 | 3eccf65ab880d43cceb8c2c877d2606d8a60ca2164c7459246a4f4c7677db2cc |
| mjx-ncm-cyss.woff2 | deafc77bf727a846a89923c3353378a66d8e2b331a0943f9e5da8d175976e2ad |
| mjx-ncm-cyssb.woff2 | 5cfeaebdbf462af0cf7e468140148c8f3665d8f1e88ca7496a6a4ce776a095b1 |
| mjx-ncm-cyssbi.woff2 | 75ff63948be2b93f01f9ce92b7c01ceab3b165a98ec130b6f68e21e2a4a4243f |
| mjx-ncm-cyssi.woff2 | 630b634836e36fbad04d9589eba321a686a5bc7a8552d031dfa51fa36f7e5aac |
| mjx-ncm-ds.woff2 | 55fa7c9ee61db7ea6d5cd498016ac5c559bf4c48c8ade952c46196ba82384064 |
| mjx-ncm-dv.woff2 | 7a4b89bd20aa94003f6a88fcac7b37823503c894337dc3767e8602b934385c0f |
| mjx-ncm-em.woff2 | e438743a1e217e6dd12adc0e3dd7ad99f06b6bd61836561aa07de48cc960dfcb |
| mjx-ncm-f.woff2 | 807ba2d061385e9429ffdc99436374dd30bb818b7fb2a93e37a73f0cc6cfc46c |
| mjx-ncm-fb.woff2 | 9e27ed005c6303eecaae27e775b11b8eac3d2c85be5b62653ae1f93df124fc51 |
| mjx-ncm-gk.woff2 | 5086fdd28a4ae938452a4b177736d040f5b4495f1907da4dd9a5cb24cf0cdba4 |
| mjx-ncm-gkb.woff2 | 6174a6b8ace7fbbedd4e4517689d9ef7acc6e260328791f906aa8a8f57ddd378 |
| mjx-ncm-gkbi.woff2 | 81463eeb14b85e7a63979c773050fda8d59a6c36dd9a682f38635b8cce85260f |
| mjx-ncm-gki.woff2 | 0185126699ae80e0c27dbdfa136d4aeb66cf7b1640b8b7965ea74e7987c2c29a |
| mjx-ncm-gkss.woff2 | eb9a2b7cbde5ace2303b6e5cc1938c22fcc4941ce4203ae338f04e5cd84fbbd3 |
| mjx-ncm-gkssb.woff2 | 60c43c0b2ac2f7dae55875707a989c353aeba12ab1865f753f23ed165d132c72 |
| mjx-ncm-gkssbi.woff2 | d2f5f0fa60dd3ceed92b6e58d04114001b965ef5668b1a307036cd8e07f30fdc |
| mjx-ncm-gkssi.woff2 | aaa7ddddaecf4f318edb90602f0281d35b8c9f8cd055d037bf3171be3f0c2966 |
| mjx-ncm-he.woff2 | 6a735a8f6216f182a0cb1e2b0878f2ce4b24ec30e633fc21322ce22fa8607696 |
| mjx-ncm-heb.woff2 | 935d2cc9e8ec70822d0b45eff866645f2fa9399bc0a8ddc5b14802c1c21dcd19 |
| mjx-ncm-hebi.woff2 | 1a801f9c0de1b2ccf5221492c5a0d4c39c5d9233330bc458e9126034df18f3c3 |
| mjx-ncm-hei.woff2 | 0c94513a5b8724e94ab07839334ca325e1093c62ac7b4141294fdc6efbb892ae |
| mjx-ncm-i.woff2 | ff33843d3b60c451b8fb4680e8a5d086cb16c3a1e86c7f16d71b25262f826d68 |
| mjx-ncm-lb.woff2 | 0e6f9f50a9013c6ce6a8b9ee138be2b6414f16cc1349281ccfa590389ab7a88f |
| mjx-ncm-li.woff2 | 8e613a25ee3a5dda011fb268d5e744a073f454ce0e8cfbe8f0d5735a8c9a2efe |
| mjx-ncm-lib.woff2 | 83b129be6b3d81c9a7087aabdfcfa4324793fc1d6634a1f96420db8377cef9bf |
| mjx-ncm-lo.woff2 | 648bf3b073453537e31856d160ddd02198da3469843f4110a97ed50ace3e48cd |
| mjx-ncm-lr.woff2 | e8e1f9f71f4ea8daf6655c131ec273d86bf79d951abe1c09ea43b6ec53b4e522 |
| mjx-ncm-lt.woff2 | ff9f74c262c17bd28903104f77f5d6fd666fd6a8a83af2d208eb465c8da8e553 |
| mjx-ncm-m.woff2 | e75f56e5a38356f27803f37a902e2a0ab6bfa35bbbd05eed57cf843a910eae75 |
| mjx-ncm-mar.woff2 | 7400843ff7a58f742971eda9c74aaf272d2808ec4192981806593598fe415907 |
| mjx-ncm-mi.woff2 | a033afc1ea52f834cb8077c200893a6f88681b81c88f34a03e03fb2492412429 |
| mjx-ncm-ml.woff2 | 93a1d4a6312141f24fabfa0386f5f59ea0ed16c96732f91ab3d633cfedce4957 |
| mjx-ncm-mm.woff2 | 9090ab9f0d7c5b0ab458df758158710f0e5038cbe318bc3e8d5a42a1419411d1 |
| mjx-ncm-msh.woff2 | c65b2db9fcb2b1d63739a3a735227bb022f6386f93e732e81c81ab4e80f95e57 |
| mjx-ncm-mx.woff2 | 0d8c5969f55c143b226282e54033f9f32b330a5abb626e73d9eef6da4ab13cde |
| mjx-ncm-n.woff2 | 6dcaf2ebcd1d1490fb6e85c3647ae0ed0d0a47ac43efe136c5328519f1da117b |
| mjx-ncm-ob.woff2 | 26dd14f86b65322d3fcf7b9a39f6cb04919dc85ec3ccea133dd10ea53cd2eceb |
| mjx-ncm-os.woff2 | d1d2a5396eafcd455f298e87eae9a4f2d7c7a7030d6c58fce16442ced46de4d7 |
| mjx-ncm-ph.woff2 | 201c3759edf766eba7a3553e9fe8168fb61090d472cda6d26ae8bf79ebdd42ba |
| mjx-ncm-phb.woff2 | a486b7c8495328fd659badb068d9801c39ffa946c3d8fe1287d14fa8409f3dca |
| mjx-ncm-phbi.woff2 | f00610244688789ce72faedfeff6895c8e3d348352fd0792845e2caa152dc375 |
| mjx-ncm-phi.woff2 | 7ec5eca55aefa6f9522db9a7eb0ba4b62ecca3aea4d4d9e957b0f951ad953b40 |
| mjx-ncm-phss.woff2 | fa635aa8f3e4f105e44b5435812fda4293796d0cbaa7b2cd98a7d0b7914a62d2 |
| mjx-ncm-phssb.woff2 | 6feaef68a860c32379bcddbc5c6fc46a53e25942e9c8a52b0db1c262dca5db86 |
| mjx-ncm-phssbi.woff2 | 3f449b868e8832fe82a1981ef3b0a334c889a42809ad1678f567210d188775d0 |
| mjx-ncm-phssi.woff2 | bf8909c78f81450aeb4c0aaaa6556fc269c8ff873718834bc594d57a8cfc88d9 |
| mjx-ncm-pu.woff2 | 495d1c4a40b57e0cfbaa7ad1b3281eff8dbd3562959dbde1fad58198739d4bd5 |
| mjx-ncm-pub.woff2 | 746416d14d183491ee99b897a4fe38849420585fefc22c3de34b28a25d0a137c |
| mjx-ncm-pubi.woff2 | 6a143f2d149c4f996a83949566f7403392505cefa4e3585e194be368b28c746f |
| mjx-ncm-pui.woff2 | 98356729e9585e164b3cf488225fcfc62e74f2fea327522e864bbb53c05a0a99 |
| mjx-ncm-rb.woff2 | 5c8c39f391adc2cef60afc74c4463e79541272e6c188f7efd336846a974e7cf7 |
| mjx-ncm-s.woff2 | d35959160704891ed2e2bbe40e8bf35cfbbfa06ba3edfce35ffc957604eea628 |
| mjx-ncm-s3.woff2 | e2e89eedebb6fcbdcdbd004a50851c295a26bb8247ea96827e88898b3262e825 |
| mjx-ncm-s4.woff2 | 8358f1daeccf586e443217fc8235b17e6e84d75c63c5c3b4896b70500943de23 |
| mjx-ncm-s5.woff2 | 4c1abef2f5676a4578d24eaefb4f07335fe9cf1b682d0a604391058eaf69d275 |
| mjx-ncm-s6.woff2 | 3c6b241ce6cd8624cf7d52fa643482139d6836394909cfcb9d288dafa6cb001c |
| mjx-ncm-s7.woff2 | 30b429054c4daf2ff2679d1c644bc91ff093f9925c93c25bccfe4b1ef9d81f0f |
| mjx-ncm-sb.woff2 | 49368a11a3abdb38d61e5eb23263bc2cca85473d6bd59ee4d9790ca1d981a6bb |
| mjx-ncm-sh.woff2 | 3481446acd6b8387ed1d0b91af9873200d1f378aaf931c1e4f728d13babb336b |
| mjx-ncm-shb.woff2 | 2d3821e87f3123e98a83d65f73076c26eef6dc84c90049ed958101142680cd0c |
| mjx-ncm-shbi.woff2 | 30b30e946801450e0ba23ef4d476a48dd571bc6613badf9108703650bd0a5511 |
| mjx-ncm-shi.woff2 | 14567da5867f27f942eebb08008c158eb6e39bf171a723e8464de7882a79e275 |
| mjx-ncm-so.woff2 | 6e63343722538572b8fbf86dfac75aa90d94180236ccb756101904887ff2fe3e |
| mjx-ncm-ss.woff2 | d0374dd78c46443eb5d24cb7b9bfb70223dad02f402c7e067328db0f0fa4c874 |
| mjx-ncm-ssb.woff2 | 858e5774c936065a4b40e670004028b54c56fe91ff57771879fee7ace28e285d |
| mjx-ncm-ssbi.woff2 | 799257bff4a868754ebbd80a25e3fcb15bded66005b0b90c358797ec9535fdde |
| mjx-ncm-ssbix.woff2 | dd390467fef0337857f471a4eaefe9271f2c4fd9c3234e685427c8db9d911e87 |
| mjx-ncm-ssbx.woff2 | 5ca3f6d99f2f1d3d7e7f32cb20b637c5c2a1a9ff8349ed45c72afc5ab71829d7 |
| mjx-ncm-ssi.woff2 | a8f84256a414918cd01fc594c4dd8cb29d7c908e3536200e50357725de8f9883 |
| mjx-ncm-ssix.woff2 | 827a7494e70293b96e6b95fddc3a01f329661d9d85e944af9b7a4be6cdb1ffd0 |
| mjx-ncm-sslb.woff2 | e4b3ee31bc2630ecb97de5de0551b154655a9c8c3218227bfbb524f6e65ab21b |
| mjx-ncm-ssli.woff2 | 8dacfee89ded1e1185edef2bda318c9cb9f3df55a880e36c8759edddbe4d0e50 |
| mjx-ncm-sslib.woff2 | e5add180f95f2d8894abe251aa544ca569611f0e23eac01f184e810d98595b20 |
| mjx-ncm-sslr.woff2 | e62aecfb96f85cae8d8128b63c9fb50dc313a2d928d4108d521915a59ac4eae8 |
| mjx-ncm-ssx.woff2 | e9d6cef669ccc864f193c1ff7e778fa2897cdf9d82e3198004ca65a613e7df81 |
| mjx-ncm-sy.woff2 | eba20ca513d5e11ac19282f6b51d59b162cee0d8fcae4ef1078fe39ebba41af6 |
| mjx-ncm-syb.woff2 | b0cc12efaa291e46bb5e381f684bca9d08cc5eb67746154b353889a0c7b667dc |
| mjx-ncm-sybi.woff2 | 411b7361ee0dcf4f9c4be8a20244149692f1a56d80795f25cc98f998a2d9f967 |
| mjx-ncm-syi.woff2 | 1d2e4e8030c2add700e641d6401d2b9d5374e228507acef16abefb7b8bb90652 |
| mjx-ncm-u-a.woff2 | 0a90315e8de88d568186257c9424bd4afc29b213104c8f9eb8ea67f2ffb774d9 |
| mjx-ncm-u.woff2 | a2ee7f53173e685c3e04490f9a1531169ba0e669b8e3a5bfd07717b43326f02c |
| mjx-ncm-v.woff2 | 5d8a55d28ac23f71a6966ca1ae7d7b34f534f23f59806f8abae8ac1b6853b565 |
| mjx-ncm-vx.woff2 | 8da9e1d5139531597fc248dbbb0bd28250a26fdd017dbef1cd6847525e933d6d |
| mjx-ncm-zero.woff2 | 5871b40a61aec9c13826851150208b19e06a15419bebac653e638437daafbcfc |

## GUST-FONT-LICENSE.txt

Authoritative license text: https://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt; SHA-256 `49ea6cb9257bbee0a3979c48a774cd221550ac1c20c95549efe45fc99cc18050`. These stable license texts interpret the declaration embedded in the exact 4.1.3 font bytes.

```text
% This is version 1.0, dated 22 June 2009, of the GUST Font License.
% (GUST is the Polish TeX Users Group, http://www.gust.org.pl)
%
% For the most recent version of this license see
% http://www.gust.org.pl/fonts/licenses/GUST-FONT-LICENSE.txt
% or
% http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt
%
% This work may be distributed and/or modified under the conditions
% of the LaTeX Project Public License, either version 1.3c of this
% license or (at your option) any later version.
%
% Please also observe the following clause:
% 1) it is requested, but not legally required, that derived works be
%    distributed only after changing the names of the fonts comprising this
%    work and given in an accompanying "manifest", and that the
%    files comprising the Work, as listed in the manifest, also be given
%    new names. Any exceptions to this request are also given in the
%    manifest.
%
%    We recommend the manifest be given in a separate file named
%    MANIFEST-<fontid>.txt, where <fontid> is some unique identification
%    of the font family. If a separate "readme" file accompanies the Work,
%    we recommend a name of the form README-<fontid>.txt.
%
% The latest version of the LaTeX Project Public License is in
% http://www.latex-project.org/lppl.txt and version 1.3c or later
% is part of all distributions of LaTeX version 2006/05/20 or later.

```

## LPPL-1.3c.txt

Authoritative license text: https://www.latex-project.org/lppl/lppl-1-3c.txt; SHA-256 `c1ae6e179a6d28bbd5c483fbacc744acc75e922d598281dc3390aab26126e163`. These stable license texts interpret the declaration embedded in the exact 4.1.3 font bytes.

```text
The LaTeX Project Public License
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

LPPL Version 1.3c  2008-05-04

Copyright 1999 2002-2008 LaTeX3 Project
    Everyone is allowed to distribute verbatim copies of this
    license document, but modification of it is not allowed.


PREAMBLE
========

The LaTeX Project Public License (LPPL) is the primary license under
which the LaTeX kernel and the base LaTeX packages are distributed.

You may use this license for any work of which you hold the copyright
and which you wish to distribute.  This license may be particularly
suitable if your work is TeX-related (such as a LaTeX package), but
it is written in such a way that you can use it even if your work is
unrelated to TeX.

The section `WHETHER AND HOW TO DISTRIBUTE WORKS UNDER THIS LICENSE',
below, gives instructions, examples, and recommendations for authors
who are considering distributing their works under this license.

This license gives conditions under which a work may be distributed
and modified, as well as conditions under which modified versions of
that work may be distributed.

We, the LaTeX3 Project, believe that the conditions below give you
the freedom to make and distribute modified versions of your work
that conform with whatever technical specifications you wish while
maintaining the availability, integrity, and reliability of
that work.  If you do not see how to achieve your goal while
meeting these conditions, then read the document `cfgguide.tex'
and `modguide.tex' in the base LaTeX distribution for suggestions.


DEFINITIONS
===========

In this license document the following terms are used:

   `Work'
    Any work being distributed under this License.

   `Derived Work'
    Any work that under any applicable law is derived from the Work.

   `Modification'
    Any procedure that produces a Derived Work under any applicable
    law -- for example, the production of a file containing an
    original file associated with the Work or a significant portion of
    such a file, either verbatim or with modifications and/or
    translated into another language.

   `Modify'
    To apply any procedure that produces a Derived Work under any
    applicable law.

   `Distribution'
    Making copies of the Work available from one person to another, in
    whole or in part.  Distribution includes (but is not limited to)
    making any electronic components of the Work accessible by
    file transfer protocols such as FTP or HTTP or by shared file
    systems such as Sun's Network File System (NFS).

   `Compiled Work'
    A version of the Work that has been processed into a form where it
    is directly usable on a computer system.  This processing may
    include using installation facilities provided by the Work,
    transformations of the Work, copying of components of the Work, or
    other activities.  Note that modification of any installation
    facilities provided by the Work constitutes modification of the Work.

   `Current Maintainer'
    A person or persons nominated as such within the Work.  If there is
    no such explicit nomination then it is the `Copyright Holder' under
    any applicable law.

   `Base Interpreter'
    A program or process that is normally needed for running or
    interpreting a part or the whole of the Work.

    A Base Interpreter may depend on external components but these
    are not considered part of the Base Interpreter provided that each
    external component clearly identifies itself whenever it is used
    interactively.  Unless explicitly specified when applying the
    license to the Work, the only applicable Base Interpreter is a
    `LaTeX-Format' or in the case of files belonging to the
    `LaTeX-format' a program implementing the `TeX language'.



CONDITIONS ON DISTRIBUTION AND MODIFICATION
===========================================

1.  Activities other than distribution and/or modification of the Work
are not covered by this license; they are outside its scope.  In
particular, the act of running the Work is not restricted and no
requirements are made concerning any offers of support for the Work.

2.  You may distribute a complete, unmodified copy of the Work as you
received it.  Distribution of only part of the Work is considered
modification of the Work, and no right to distribute such a Derived
Work may be assumed under the terms of this clause.

3.  You may distribute a Compiled Work that has been generated from a
complete, unmodified copy of the Work as distributed under Clause 2
above, as long as that Compiled Work is distributed in such a way that
the recipients may install the Compiled Work on their system exactly
as it would have been installed if they generated a Compiled Work
directly from the Work.

4.  If you are the Current Maintainer of the Work, you may, without
restriction, modify the Work, thus creating a Derived Work.  You may
also distribute the Derived Work without restriction, including
Compiled Works generated from the Derived Work.  Derived Works
distributed in this manner by the Current Maintainer are considered to
be updated versions of the Work.

5.  If you are not the Current Maintainer of the Work, you may modify
your copy of the Work, thus creating a Derived Work based on the Work,
and compile this Derived Work, thus creating a Compiled Work based on
the Derived Work.

6.  If you are not the Current Maintainer of the Work, you may
distribute a Derived Work provided the following conditions are met
for every component of the Work unless that component clearly states
in the copyright notice that it is exempt from that condition.  Only
the Current Maintainer is allowed to add such statements of exemption
to a component of the Work.

  a. If a component of this Derived Work can be a direct replacement
     for a component of the Work when that component is used with the
     Base Interpreter, then, wherever this component of the Work
     identifies itself to the user when used interactively with that
     Base Interpreter, the replacement component of this Derived Work
     clearly and unambiguously identifies itself as a modified version
     of this component to the user when used interactively with that
     Base Interpreter.

  b. Every component of the Derived Work contains prominent notices
     detailing the nature of the changes to that component, or a
     prominent reference to another file that is distributed as part
     of the Derived Work and that contains a complete and accurate log
     of the changes.

  c. No information in the Derived Work implies that any persons,
     including (but not limited to) the authors of the original version
     of the Work, provide any support, including (but not limited to)
     the reporting and handling of errors, to recipients of the
     Derived Work unless those persons have stated explicitly that
     they do provide such support for the Derived Work.

  d. You distribute at least one of the following with the Derived Work:

       1. A complete, unmodified copy of the Work;
          if your distribution of a modified component is made by
          offering access to copy the modified component from a
          designated place, then offering equivalent access to copy
          the Work from the same or some similar place meets this
          condition, even though third parties are not compelled to
          copy the Work along with the modified component;

       2. Information that is sufficient to obtain a complete,
          unmodified copy of the Work.

7.  If you are not the Current Maintainer of the Work, you may
distribute a Compiled Work generated from a Derived Work, as long as
the Derived Work is distributed to all recipients of the Compiled
Work, and as long as the conditions of Clause 6, above, are met with
regard to the Derived Work.

8.  The conditions above are not intended to prohibit, and hence do not
apply to, the modification, by any method, of any component so that it
becomes identical to an updated version of that component of the Work as
it is distributed by the Current Maintainer under Clause 4, above.

9.  Distribution of the Work or any Derived Work in an alternative
format, where the Work or that Derived Work (in whole or in part) is
then produced by applying some process to that format, does not relax or
nullify any sections of this license as they pertain to the results of
applying that process.

10. a. A Derived Work may be distributed under a different license
       provided that license itself honors the conditions listed in
       Clause 6 above, in regard to the Work, though it does not have
       to honor the rest of the conditions in this license.

    b. If a Derived Work is distributed under a different license, that
       Derived Work must provide sufficient documentation as part of
       itself to allow each recipient of that Derived Work to honor the
       restrictions in Clause 6 above, concerning changes from the Work.

11. This license places no restrictions on works that are unrelated to
the Work, nor does this license place any restrictions on aggregating
such works with the Work by any means.

12.  Nothing in this license is intended to, or may be used to, prevent
complete compliance by all parties with all applicable laws.


NO WARRANTY
===========

There is no warranty for the Work.  Except when otherwise stated in
writing, the Copyright Holder provides the Work `as is', without
warranty of any kind, either expressed or implied, including, but not
limited to, the implied warranties of merchantability and fitness for a
particular purpose.  The entire risk as to the quality and performance
of the Work is with you.  Should the Work prove defective, you assume
the cost of all necessary servicing, repair, or correction.

In no event unless required by applicable law or agreed to in writing
will The Copyright Holder, or any author named in the components of the
Work, or any other party who may distribute and/or modify the Work as
permitted above, be liable to you for damages, including any general,
special, incidental or consequential damages arising out of any use of
the Work or out of inability to use the Work (including, but not limited
to, loss of data, data being rendered inaccurate, or losses sustained by
anyone as a result of any failure of the Work to operate with any other
programs), even if the Copyright Holder or said author or said other
party has been advised of the possibility of such damages.


MAINTENANCE OF THE WORK
=======================

The Work has the status `author-maintained' if the Copyright Holder
explicitly and prominently states near the primary copyright notice in
the Work that the Work can only be maintained by the Copyright Holder
or simply that it is `author-maintained'.

The Work has the status `maintained' if there is a Current Maintainer
who has indicated in the Work that they are willing to receive error
reports for the Work (for example, by supplying a valid e-mail
address). It is not required for the Current Maintainer to acknowledge
or act upon these error reports.

The Work changes from status `maintained' to `unmaintained' if there
is no Current Maintainer, or the person stated to be Current
Maintainer of the work cannot be reached through the indicated means
of communication for a period of six months, and there are no other
significant signs of active maintenance.

You can become the Current Maintainer of the Work by agreement with
any existing Current Maintainer to take over this role.

If the Work is unmaintained, you can become the Current Maintainer of
the Work through the following steps:

 1.  Make a reasonable attempt to trace the Current Maintainer (and
     the Copyright Holder, if the two differ) through the means of
     an Internet or similar search.

 2.  If this search is successful, then enquire whether the Work
     is still maintained.

  a. If it is being maintained, then ask the Current Maintainer
     to update their communication data within one month.

  b. If the search is unsuccessful or no action to resume active
     maintenance is taken by the Current Maintainer, then announce
     within the pertinent community your intention to take over
     maintenance.  (If the Work is a LaTeX work, this could be
     done, for example, by posting to comp.text.tex.)

 3a. If the Current Maintainer is reachable and agrees to pass
     maintenance of the Work to you, then this takes effect
     immediately upon announcement.

  b. If the Current Maintainer is not reachable and the Copyright
     Holder agrees that maintenance of the Work be passed to you,
     then this takes effect immediately upon announcement.

 4.  If you make an `intention announcement' as described in 2b. above
     and after three months your intention is challenged neither by
     the Current Maintainer nor by the Copyright Holder nor by other
     people, then you may arrange for the Work to be changed so as
     to name you as the (new) Current Maintainer.

 5.  If the previously unreachable Current Maintainer becomes
     reachable once more within three months of a change completed
     under the terms of 3b) or 4), then that Current Maintainer must
     become or remain the Current Maintainer upon request provided
     they then update their communication data within one month.

A change in the Current Maintainer does not, of itself, alter the fact
that the Work is distributed under the LPPL license.

If you become the Current Maintainer of the Work, you should
immediately provide, within the Work, a prominent and unambiguous
statement of your status as Current Maintainer.  You should also
announce your new status to the same pertinent community as
in 2b) above.


WHETHER AND HOW TO DISTRIBUTE WORKS UNDER THIS LICENSE
======================================================

This section contains important instructions, examples, and
recommendations for authors who are considering distributing their
works under this license.  These authors are addressed as `you' in
this section.

Choosing This License or Another License
----------------------------------------

If for any part of your work you want or need to use *distribution*
conditions that differ significantly from those in this license, then
do not refer to this license anywhere in your work but, instead,
distribute your work under a different license.  You may use the text
of this license as a model for your own license, but your license
should not refer to the LPPL or otherwise give the impression that
your work is distributed under the LPPL.

The document `modguide.tex' in the base LaTeX distribution explains
the motivation behind the conditions of this license.  It explains,
for example, why distributing LaTeX under the GNU General Public
License (GPL) was considered inappropriate.  Even if your work is
unrelated to LaTeX, the discussion in `modguide.tex' may still be
relevant, and authors intending to distribute their works under any
license are encouraged to read it.

A Recommendation on Modification Without Distribution
-----------------------------------------------------

It is wise never to modify a component of the Work, even for your own
personal use, without also meeting the above conditions for
distributing the modified component.  While you might intend that such
modifications will never be distributed, often this will happen by
accident -- you may forget that you have modified that component; or
it may not occur to you when allowing others to access the modified
version that you are thus distributing it and violating the conditions
of this license in ways that could have legal implications and, worse,
cause problems for the community.  It is therefore usually in your
best interest to keep your copy of the Work identical with the public
one.  Many works provide ways to control the behavior of that work
without altering any of its licensed components.

How to Use This License
-----------------------

To use this license, place in each of the components of your work both
an explicit copyright notice including your name and the year the work
was authored and/or last substantially modified.  Include also a
statement that the distribution and/or modification of that
component is constrained by the conditions in this license.

Here is an example of such a notice and statement:

  %% pig.dtx
  %% Copyright 2008 M. Y. Name
  %
  % This work may be distributed and/or modified under the
  % conditions of the LaTeX Project Public License, either version 1.3
  % of this license or (at your option) any later version.
  % The latest version of this license is in
  %   https://www.latex-project.org/lppl.txt
  % and version 1.3c or later is part of all distributions of LaTeX
  % version 2008 or later.
  %
  % This work has the LPPL maintenance status `maintained'.
  %
  % The Current Maintainer of this work is M. Y. Name.
  %
  % This work consists of the files pig.dtx and pig.ins
  % and the derived file pig.sty.

Given such a notice and statement in a file, the conditions
given in this license document would apply, with the `Work' referring
to the three files `pig.dtx', `pig.ins', and `pig.sty' (the last being
generated from `pig.dtx' using `pig.ins'), the `Base Interpreter'
referring to any `LaTeX-Format', and both `Copyright Holder' and
`Current Maintainer' referring to the person `M. Y. Name'.

If you do not want the Maintenance section of LPPL to apply to your
Work, change `maintained' above into `author-maintained'.
However, we recommend that you use `maintained', as the Maintenance
section was added in order to ensure that your Work remains useful to
the community even when you can no longer maintain and support it
yourself.

Derived Works That Are Not Replacements
---------------------------------------

Several clauses of the LPPL specify means to provide reliability and
stability for the user community. They therefore concern themselves
with the case that a Derived Work is intended to be used as a
(compatible or incompatible) replacement of the original Work. If
this is not the case (e.g., if a few lines of code are reused for a
completely different task), then clauses 6b and 6d shall not apply.


Important Recommendations
-------------------------

 Defining What Constitutes the Work

   The LPPL requires that distributions of the Work contain all the
   files of the Work.  It is therefore important that you provide a
   way for the licensee to determine which files constitute the Work.
   This could, for example, be achieved by explicitly listing all the
   files of the Work near the copyright notice of each file or by
   using a line such as:

    % This work consists of all files listed in manifest.txt.

   in that place.  In the absence of an unequivocal list it might be
   impossible for the licensee to determine what is considered by you
   to comprise the Work and, in such a case, the licensee would be
   entitled to make reasonable conjectures as to which files comprise
   the Work.


```

## @isaacs/nonrecursive-glob-match@1.1.0

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/@isaacs/nonrecursive-glob-match/-/nonrecursive-glob-match-1.1.0.tgz

Original `node_modules/@isaacs/nonrecursive-glob-match/LICENSE.md`, SHA-256 `8a1af140fdfbf5afd3df27f7e662f989c5b963a300020dfafce42033cae9e004`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## @mathjax/mathjax-newcm-font@4.1.3

Publisher license declaration: Apache-2.0; source: https://registry.npmjs.org/@mathjax/mathjax-newcm-font/-/mathjax-newcm-font-4.1.3.tgz


## @mathjax/src@4.1.3

Publisher license declaration: Apache-2.0; source: https://registry.npmjs.org/@mathjax/src/-/src-4.1.3.tgz

Original `node_modules/@mathjax/src/LICENSE`, SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`:

```text

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

```

## @xmldom/xmldom@0.9.12

Publisher license declaration: MIT; source: https://registry.npmjs.org/@xmldom/xmldom/-/xmldom-0.9.12.tgz

Original `node_modules/@xmldom/xmldom/LICENSE`, SHA-256 `4da724fc305d81606b245b324d4d2586916b9d248b23d82183df753ace0fdf71`:

```text
Copyright 2019 - present Christopher J. Brody and other contributors, as listed in: https://github.com/xmldom/xmldom/graphs/contributors
Copyright 2012 - 2017 @jindw <jindw@xidea.org> and other contributors, as listed in: https://github.com/jindw/xmldom/graphs/contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

```

## balanced-match@4.0.4

Publisher license declaration: MIT; source: https://registry.npmjs.org/balanced-match/-/balanced-match-4.0.4.tgz

Original `node_modules/balanced-match/LICENSE.md`, SHA-256 `d408f38ffa3355c5faec517153295338892eb0f1ea43f57874bb23c6075979b5`:

```text
(MIT)

Original code Copyright Julian Gruber <julian@juliangruber.com>

Port to TypeScript Copyright Isaac Z. Schlueter <i@izs.me>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

## brace-expansion@5.0.13

Publisher license declaration: MIT; source: https://registry.npmjs.org/brace-expansion/-/brace-expansion-5.0.13.tgz

Original `node_modules/brace-expansion/LICENSE`, SHA-256 `9c63a23124d68cd30cd316a94a1a0bca34f032786df6df69fc4b5f136bac8d2e`:

```text
MIT License

Copyright Julian Gruber <julian@juliangruber.com>

TypeScript port Copyright Isaac Z. Schlueter <i@izs.me>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

## commander@14.0.3

Publisher license declaration: MIT; source: https://registry.npmjs.org/commander/-/commander-14.0.3.tgz

Original `node_modules/commander/LICENSE`, SHA-256 `04512a63dce4d2d506ad612dc0bd7681ccf6e3655f7b6eaef7dfac8323d1ec0b`:

```text
(The MIT License)

Copyright (c) 2011 TJ Holowaychuk <tj@vision-media.ca>

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

```

## glob@14.0.6

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/glob/-/glob-14.0.6.tgz

Original `node_modules/glob/LICENSE.md`, SHA-256 `a49c9ba464796f65b59fca3f1e6ca40912df1e859f575383223f7ec6c5baae09`:

```text
All packages under `src/` are licensed according to the terms in
their respective `LICENSE` or `LICENSE.md` files.

The remainder of this project is licensed under the Blue Oak
Model License, as follows:

-----

# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## lru-cache@11.5.3

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/lru-cache/-/lru-cache-11.5.3.tgz

Original `node_modules/lru-cache/LICENSE.md`, SHA-256 `8a1af140fdfbf5afd3df27f7e662f989c5b963a300020dfafce42033cae9e004`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## mhchemparser@4.2.1

Publisher license declaration: Apache-2.0; source: https://registry.npmjs.org/mhchemparser/-/mhchemparser-4.2.1.tgz

Original `node_modules/mhchemparser/LICENSE.txt`, SHA-256 `b40930bbcf80744c86c46a12bc9da056641d722716c378f5659b9e555ef833e1`:

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "{}"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright {yyyy} {name of copyright owner}

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

```

## minimatch@11.0.9

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/minimatch/-/minimatch-11.0.9.tgz

Original `node_modules/minimatch/LICENSE.md`, SHA-256 `2c7c5d22ed5a8ee968c64757710979afcd77438c48b4a265b94e615babd8a901`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules. The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice. If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

**_As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim._**

```

## minipass@7.1.3

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/minipass/-/minipass-7.1.3.tgz

Original `node_modules/minipass/LICENSE.md`, SHA-256 `8a1af140fdfbf5afd3df27f7e662f989c5b963a300020dfafce42033cae9e004`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## mj-context-menu@1.0.0

Publisher license declaration: Apache-2.0; source: https://registry.npmjs.org/mj-context-menu/-/mj-context-menu-1.0.0.tgz

Original `node_modules/mj-context-menu/LICENSE`, SHA-256 `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`:

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

```

## package-json-from-dist@1.0.1

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/package-json-from-dist/-/package-json-from-dist-1.0.1.tgz

Original `node_modules/package-json-from-dist/LICENSE.md`, SHA-256 `a49c9ba464796f65b59fca3f1e6ca40912df1e859f575383223f7ec6c5baae09`:

```text
All packages under `src/` are licensed according to the terms in
their respective `LICENSE` or `LICENSE.md` files.

The remainder of this project is licensed under the Blue Oak
Model License, as follows:

-----

# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## path-scurry@3.0.0

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/path-scurry/-/path-scurry-3.0.0.tgz

Original `node_modules/path-scurry/LICENSE.md`, SHA-256 `8a1af140fdfbf5afd3df27f7e662f989c5b963a300020dfafce42033cae9e004`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## rimraf@6.1.4

Publisher license declaration: BlueOak-1.0.0; source: https://registry.npmjs.org/rimraf/-/rimraf-6.1.4.tgz

Original `node_modules/rimraf/LICENSE.md`, SHA-256 `8a1af140fdfbf5afd3df27f7e662f989c5b963a300020dfafce42033cae9e004`:

```text
# Blue Oak Model License

Version 1.0.0

## Purpose

This license gives everyone as much permission to work with
this software as possible, while protecting contributors
from liability.

## Acceptance

In order to receive this license, you must agree to its
rules.  The rules of this license are both obligations
under that agreement and conditions to your license.
You must not do anything with this software that triggers
a rule that you cannot or will not follow.

## Copyright

Each contributor licenses you to do everything with this
software that would otherwise infringe that contributor's
copyright in it.

## Notices

You must ensure that everyone who gets a copy of
any part of this software from you, with or without
changes, also gets the text of this license or a link to
<https://blueoakcouncil.org/license/1.0.0>.

## Excuse

If anyone notifies you in writing that you have not
complied with [Notices](#notices), you can keep your
license by taking all practical steps to comply within 30
days after the notice.  If you do not do so, your license
ends immediately.

## Patent

Each contributor licenses you to do everything with this
software that would otherwise infringe any patent claims
they can license or become able to license.

## Reliability

No contributor can revoke this license.

## No Liability

***As far as the law allows, this software comes as is,
without any warranty or condition, and no contributor
will be liable to anyone for any damages related to this
software or this license, under any kind of legal claim.***

```

## speech-rule-engine@5.0.0-rc.4

Publisher license declaration: Apache-2.0; source: https://registry.npmjs.org/speech-rule-engine/-/speech-rule-engine-5.0.0-rc.4.tgz

Original `node_modules/speech-rule-engine/LICENSE`, SHA-256 `0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594`:

```text

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

```

## wicked-good-xpath@1.3.0

Publisher license declaration: MIT; source: https://registry.npmjs.org/wicked-good-xpath/-/wicked-good-xpath-1.3.0.tgz

Original `node_modules/wicked-good-xpath/LICENSE`, SHA-256 `1691999de7a5de50698e735c25506ea8ab6b71d008d27ef9e1400a5075000e78`:

```text

The MIT License

Copyright (c) 2007 Cybozu Labs, Inc.
Copyright (c) 2012 Google Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

```

## Host Node

Node is host-required, not redistributed as a binary. Preparation copies the selected distribution’s complete LICENSE (including its third-party notices) to licenses/Node-LICENSE and binds its hash and Mach-O dependency metadata. No standalone or macOS13.0 compatibility claim is made.

## Independent pinned font evidence (FreeType)

Development-only FT_Get_Sfnt_Name read all 105 exact pinned WOFF2 files: 84 original GUST notices; 21 MathJax-added original GUST notices; parse errors 0. name5 values are embedded font version metadata, not npm package version. Official GUST/LPPL text retrieval was performed separately during allowed materialization. These are preservation evidence, not final DocsAudit or legal/policy acceptance. No current CTAN newcm licensing is inferred for these bytes.

Official term acquisition records:

```json
[
  {
    "url": "https://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt",
    "retrievedUTC": "2026-11-17T08:23:54.278626+00:00",
    "status": 200,
    "contentType": "text/plain",
    "bytes": 1377,
    "sha256": "49ea6cb9257bbee0a3979c48a774cd221550ac1c20c95549efe45fc99cc18050",
    "exit": 0
  },
  {
    "url": "https://www.latex-project.org/lppl/lppl-1-3c.txt",
    "retrievedUTC": "2026-11-17T08:23:55.051105+00:00",
    "status": 200,
    "contentType": "text/plain",
    "bytes": 19036,
    "sha256": "c1ae6e179a6d28bbd5c483fbacc744acc75e922d598281dc3390aab26126e163",
    "exit": 0
  }
]
```

<!-- native-font-preservation-v1
{"count":105,"classes":{"original-gust":84,"mathjax-plus-original-gust":21},"fonts":[{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ab.woff2","sha256":"9813052b6bca662c7d7242e35e6b754de3edb6c469dc4c3af747a6b1d7de9962","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-abi.woff2","sha256":"544e713025065edf43e9b34b671bc47203d0879c73cccbaa000093ff07ae09da","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ai.woff2","sha256":"ba7e5230b13bc7744e8b51f3cff12d43c4590b18122b4acd6b9bd03b9588d9b0","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ar.woff2","sha256":"9e942b15ecbf57c84324aa27fdfbea5679de4bee0e1a578eb209153c60d8ad79","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-arl.woff2","sha256":"ac5a25c0ab7082074f811aecf807cb16dc087879e3d58b5e2893eae0d6f1c449","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-b-a.woff2","sha256":"036467b277fb41f43d7a37b1190bb8c9069ff9896ffad8a3ea373fc3d4dba88a","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-b.woff2","sha256":"ea04057759e00963656c9cb63070acdfa20a6ebf441b63a004032fba63c01aef","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-bi.woff2","sha256":"925f5064cbe2c9236c59821cb3ec9a411ee46ec32eaaee0fc1c5fd855fe9d098","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-br.woff2","sha256":"5276058e417131564b8e122e79564a5357bcfbe52ec99f381323f510bdab3e6c","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-brd.woff2","sha256":"dd74ff0393fc3662d30626a464c2a49e244b8c4407304fa048be097525882bfa","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-brk.woff2","sha256":"4ba8ef6cf75997b0f62b21fac1633612469d6864026dc431a2f98565f4f86666","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-c.woff2","sha256":"bfe4cd45950bd79704ad58fa97edb3d716c7d14a8a493e41ae3f537c43ada90d","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cb.woff2","sha256":"68ebec1310a6cbb92b4a968ea63e89353b06e3d06423e6073fd7e7aa0d528605","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ch.woff2","sha256":"22cf130d6ce128ec6b97e66c256b36a29e1732c85fa8c972e6b9829b88e881f1","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-chb.woff2","sha256":"5cf157d3e5ac9147a5a965d8faa6b887e11a1e9cc6138b850b722a18cb4d90e5","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-chbi.woff2","sha256":"f8495cf659299b1d7478b0b23f6e28b829ea6e690e2b511e2f83b7fbcb316cb7","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-chi.woff2","sha256":"e10555212099fcfa9185103b7ac220e772ed6648ec1bb0cd22b5f2c40f8278aa","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cy.woff2","sha256":"de6ce6188dfd327a493068d627914e3b32ddcec311e70b34f50b010da9980b14","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyb.woff2","sha256":"eea8c28d0f92014ee12419acaaf419b054eaedbf487b42aa95433c06c2fd2670","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cybi.woff2","sha256":"d2c8c1b3858fcd6987615b7fc49a2e17c999d7b91467ec9399d6cf83370282cf","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyi.woff2","sha256":"3eccf65ab880d43cceb8c2c877d2606d8a60ca2164c7459246a4f4c7677db2cc","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyss.woff2","sha256":"deafc77bf727a846a89923c3353378a66d8e2b331a0943f9e5da8d175976e2ad","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyssb.woff2","sha256":"5cfeaebdbf462af0cf7e468140148c8f3665d8f1e88ca7496a6a4ce776a095b1","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyssbi.woff2","sha256":"75ff63948be2b93f01f9ce92b7c01ceab3b165a98ec130b6f68e21e2a4a4243f","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-cyssi.woff2","sha256":"630b634836e36fbad04d9589eba321a686a5bc7a8552d031dfa51fa36f7e5aac","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ds.woff2","sha256":"55fa7c9ee61db7ea6d5cd498016ac5c559bf4c48c8ade952c46196ba82384064","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-dv.woff2","sha256":"7a4b89bd20aa94003f6a88fcac7b37823503c894337dc3767e8602b934385c0f","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-em.woff2","sha256":"e438743a1e217e6dd12adc0e3dd7ad99f06b6bd61836561aa07de48cc960dfcb","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-f.woff2","sha256":"807ba2d061385e9429ffdc99436374dd30bb818b7fb2a93e37a73f0cc6cfc46c","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-fb.woff2","sha256":"9e27ed005c6303eecaae27e775b11b8eac3d2c85be5b62653ae1f93df124fc51","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gk.woff2","sha256":"5086fdd28a4ae938452a4b177736d040f5b4495f1907da4dd9a5cb24cf0cdba4","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkb.woff2","sha256":"6174a6b8ace7fbbedd4e4517689d9ef7acc6e260328791f906aa8a8f57ddd378","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkbi.woff2","sha256":"81463eeb14b85e7a63979c773050fda8d59a6c36dd9a682f38635b8cce85260f","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gki.woff2","sha256":"0185126699ae80e0c27dbdfa136d4aeb66cf7b1640b8b7965ea74e7987c2c29a","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkss.woff2","sha256":"eb9a2b7cbde5ace2303b6e5cc1938c22fcc4941ce4203ae338f04e5cd84fbbd3","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkssb.woff2","sha256":"60c43c0b2ac2f7dae55875707a989c353aeba12ab1865f753f23ed165d132c72","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkssbi.woff2","sha256":"d2f5f0fa60dd3ceed92b6e58d04114001b965ef5668b1a307036cd8e07f30fdc","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-gkssi.woff2","sha256":"aaa7ddddaecf4f318edb90602f0281d35b8c9f8cd055d037bf3171be3f0c2966","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-he.woff2","sha256":"6a735a8f6216f182a0cb1e2b0878f2ce4b24ec30e633fc21322ce22fa8607696","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-heb.woff2","sha256":"935d2cc9e8ec70822d0b45eff866645f2fa9399bc0a8ddc5b14802c1c21dcd19","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-hebi.woff2","sha256":"1a801f9c0de1b2ccf5221492c5a0d4c39c5d9233330bc458e9126034df18f3c3","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-hei.woff2","sha256":"0c94513a5b8724e94ab07839334ca325e1093c62ac7b4141294fdc6efbb892ae","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-i.woff2","sha256":"ff33843d3b60c451b8fb4680e8a5d086cb16c3a1e86c7f16d71b25262f826d68","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-lb.woff2","sha256":"0e6f9f50a9013c6ce6a8b9ee138be2b6414f16cc1349281ccfa590389ab7a88f","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-li.woff2","sha256":"8e613a25ee3a5dda011fb268d5e744a073f454ce0e8cfbe8f0d5735a8c9a2efe","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-lib.woff2","sha256":"83b129be6b3d81c9a7087aabdfcfa4324793fc1d6634a1f96420db8377cef9bf","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-lo.woff2","sha256":"648bf3b073453537e31856d160ddd02198da3469843f4110a97ed50ace3e48cd","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-lr.woff2","sha256":"e8e1f9f71f4ea8daf6655c131ec273d86bf79d951abe1c09ea43b6ec53b4e522","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-lt.woff2","sha256":"ff9f74c262c17bd28903104f77f5d6fd666fd6a8a83af2d208eb465c8da8e553","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-m.woff2","sha256":"e75f56e5a38356f27803f37a902e2a0ab6bfa35bbbd05eed57cf843a910eae75","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-mar.woff2","sha256":"7400843ff7a58f742971eda9c74aaf272d2808ec4192981806593598fe415907","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-mi.woff2","sha256":"a033afc1ea52f834cb8077c200893a6f88681b81c88f34a03e03fb2492412429","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ml.woff2","sha256":"93a1d4a6312141f24fabfa0386f5f59ea0ed16c96732f91ab3d633cfedce4957","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-mm.woff2","sha256":"9090ab9f0d7c5b0ab458df758158710f0e5038cbe318bc3e8d5a42a1419411d1","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-msh.woff2","sha256":"c65b2db9fcb2b1d63739a3a735227bb022f6386f93e732e81c81ab4e80f95e57","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-mx.woff2","sha256":"0d8c5969f55c143b226282e54033f9f32b330a5abb626e73d9eef6da4ab13cde","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-n.woff2","sha256":"6dcaf2ebcd1d1490fb6e85c3647ae0ed0d0a47ac43efe136c5328519f1da117b","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ob.woff2","sha256":"26dd14f86b65322d3fcf7b9a39f6cb04919dc85ec3ccea133dd10ea53cd2eceb","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-os.woff2","sha256":"d1d2a5396eafcd455f298e87eae9a4f2d7c7a7030d6c58fce16442ced46de4d7","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ph.woff2","sha256":"201c3759edf766eba7a3553e9fe8168fb61090d472cda6d26ae8bf79ebdd42ba","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phb.woff2","sha256":"a486b7c8495328fd659badb068d9801c39ffa946c3d8fe1287d14fa8409f3dca","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phbi.woff2","sha256":"f00610244688789ce72faedfeff6895c8e3d348352fd0792845e2caa152dc375","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phi.woff2","sha256":"7ec5eca55aefa6f9522db9a7eb0ba4b62ecca3aea4d4d9e957b0f951ad953b40","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phss.woff2","sha256":"fa635aa8f3e4f105e44b5435812fda4293796d0cbaa7b2cd98a7d0b7914a62d2","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phssb.woff2","sha256":"6feaef68a860c32379bcddbc5c6fc46a53e25942e9c8a52b0db1c262dca5db86","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phssbi.woff2","sha256":"3f449b868e8832fe82a1981ef3b0a334c889a42809ad1678f567210d188775d0","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-phssi.woff2","sha256":"bf8909c78f81450aeb4c0aaaa6556fc269c8ff873718834bc594d57a8cfc88d9","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-pu.woff2","sha256":"495d1c4a40b57e0cfbaa7ad1b3281eff8dbd3562959dbde1fad58198739d4bd5","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-pub.woff2","sha256":"746416d14d183491ee99b897a4fe38849420585fefc22c3de34b28a25d0a137c","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-pubi.woff2","sha256":"6a143f2d149c4f996a83949566f7403392505cefa4e3585e194be368b28c746f","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-pui.woff2","sha256":"98356729e9585e164b3cf488225fcfc62e74f2fea327522e864bbb53c05a0a99","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-rb.woff2","sha256":"5c8c39f391adc2cef60afc74c4463e79541272e6c188f7efd336846a974e7cf7","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s.woff2","sha256":"d35959160704891ed2e2bbe40e8bf35cfbbfa06ba3edfce35ffc957604eea628","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s3.woff2","sha256":"e2e89eedebb6fcbdcdbd004a50851c295a26bb8247ea96827e88898b3262e825","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s4.woff2","sha256":"8358f1daeccf586e443217fc8235b17e6e84d75c63c5c3b4896b70500943de23","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s5.woff2","sha256":"4c1abef2f5676a4578d24eaefb4f07335fe9cf1b682d0a604391058eaf69d275","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s6.woff2","sha256":"3c6b241ce6cd8624cf7d52fa643482139d6836394909cfcb9d288dafa6cb001c","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-s7.woff2","sha256":"30b429054c4daf2ff2679d1c644bc91ff093f9925c93c25bccfe4b1ef9d81f0f","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sb.woff2","sha256":"49368a11a3abdb38d61e5eb23263bc2cca85473d6bd59ee4d9790ca1d981a6bb","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sh.woff2","sha256":"3481446acd6b8387ed1d0b91af9873200d1f378aaf931c1e4f728d13babb336b","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-shb.woff2","sha256":"2d3821e87f3123e98a83d65f73076c26eef6dc84c90049ed958101142680cd0c","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-shbi.woff2","sha256":"30b30e946801450e0ba23ef4d476a48dd571bc6613badf9108703650bd0a5511","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-shi.woff2","sha256":"14567da5867f27f942eebb08008c158eb6e39bf171a723e8464de7882a79e275","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-so.woff2","sha256":"6e63343722538572b8fbf86dfac75aa90d94180236ccb756101904887ff2fe3e","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ss.woff2","sha256":"d0374dd78c46443eb5d24cb7b9bfb70223dad02f402c7e067328db0f0fa4c874","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssb.woff2","sha256":"858e5774c936065a4b40e670004028b54c56fe91ff57771879fee7ace28e285d","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssbi.woff2","sha256":"799257bff4a868754ebbd80a25e3fcb15bded66005b0b90c358797ec9535fdde","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssbix.woff2","sha256":"dd390467fef0337857f471a4eaefe9271f2c4fd9c3234e685427c8db9d911e87","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssbx.woff2","sha256":"5ca3f6d99f2f1d3d7e7f32cb20b637c5c2a1a9ff8349ed45c72afc5ab71829d7","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssi.woff2","sha256":"a8f84256a414918cd01fc594c4dd8cb29d7c908e3536200e50357725de8f9883","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssix.woff2","sha256":"827a7494e70293b96e6b95fddc3a01f329661d9d85e944af9b7a4be6cdb1ffd0","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sslb.woff2","sha256":"e4b3ee31bc2630ecb97de5de0551b154655a9c8c3218227bfbb524f6e65ab21b","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssli.woff2","sha256":"8dacfee89ded1e1185edef2bda318c9cb9f3df55a880e36c8759edddbe4d0e50","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sslib.woff2","sha256":"e5add180f95f2d8894abe251aa544ca569611f0e23eac01f184e810d98595b20","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sslr.woff2","sha256":"e62aecfb96f85cae8d8128b63c9fb50dc313a2d928d4108d521915a59ac4eae8","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-ssx.woff2","sha256":"e9d6cef669ccc864f193c1ff7e778fa2897cdf9d82e3198004ca65a613e7df81","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sy.woff2","sha256":"eba20ca513d5e11ac19282f6b51d59b162cee0d8fcae4ef1078fe39ebba41af6","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-syb.woff2","sha256":"b0cc12efaa291e46bb5e381f684bca9d08cc5eb67746154b353889a0c7b667dc","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-sybi.woff2","sha256":"411b7361ee0dcf4f9c4be8a20244149692f1a56d80795f25cc98f998a2d9f967","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-syi.woff2","sha256":"1d2e4e8030c2add700e641d6401d2b9d5374e228507acef16abefb7b8bb90652","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-u-a.woff2","sha256":"0a90315e8de88d568186257c9424bd4afc29b213104c8f9eb8ea67f2ffb774d9","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-u.woff2","sha256":"a2ee7f53173e685c3e04490f9a1531169ba0e669b8e3a5bfd07717b43326f02c","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-v.woff2","sha256":"5d8a55d28ac23f71a6966ca1ae7d7b34f534f23f59806f8abae8ac1b6853b565","category":"mathjax-plus-original-gust","noticeSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"36f71d171b3d313d3f55415bae3cf5365c590811180b3208a1faec265687a8ba"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"Copyright (c) 2024 MathJax, Inc. (www.mathjax.org)\nOriginal copyright:\n(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"86de14775ec14230211da439a8c6019e2b7f9802a2070f8467246808ea25a679"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-vx.woff2","sha256":"8da9e1d5139531597fc248dbbb0bd28250a26fdd017dbef1cd6847525e933d6d","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]},{"path":"node_modules/@mathjax/mathjax-newcm-font/chtml/woff2/mjx-ncm-zero.woff2","sha256":"5871b40a61aec9c13826851150208b19e06a15419bebac653e638437daafbcfc","category":"original-gust","noticeSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662","names":[{"nameID":0,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":5,"platform":0,"encoding":4,"language":0,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":0,"encoding":4,"language":0,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":0,"platform":1,"encoding":0,"language":0,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e424465559a6b70d4c57333052fec4cedfef908edeedadae4c1acb102c14a662"},{"nameID":5,"platform":1,"encoding":0,"language":0,"value":"1.0.0","rawSHA256":"92521fc3cbd964bdc9f584a991b89fddaa5754ed1cc96d6d42445338669c1305"},{"nameID":13,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":14,"platform":1,"encoding":0,"language":0,"value":" ","rawSHA256":"36a9e7f1c95b82ffb99743e0c5c4ce95d83c9a430aac59f84ef3cbfab6145068"},{"nameID":0,"platform":3,"encoding":1,"language":1033,"value":"(C) 2019-2021 Antonis Tsolomitis. \nThis work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.","rawSHA256":"e0425afafc23b93b759b71620992992752be45c1453411af27f56cf4a648ecb2"},{"nameID":5,"platform":3,"encoding":1,"language":1033,"value":"1.0.0","rawSHA256":"655367382d2ea98776e91ebc971e889de2c25bc2ad86ec65154a9a1f00b60445"},{"nameID":13,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"},{"nameID":14,"platform":3,"encoding":1,"language":1033,"value":" ","rawSHA256":"474f2af47544e9c7ce4338cabd43c5ca1c26432b7300ce387406157ea433891f"}]}]}
-->
