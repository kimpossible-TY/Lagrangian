#import "@local/text-utils:0.1.2": paragraph-tab, paragraph_tab, apply-paragraph-tabs, highlighted
#show: apply-paragraph-tabs

= Paragraph tabs

#paragraph_tab
lowercase paragraph starts after a tab and wraps onto additional lines when the reading column is narrow.

#paragraph-tab
Uppercase paragraph keeps its original letter case.

#paragraph_tab
7 remains a digit after its paragraph tab.

#paragraph_tab
$x^2 + y^2 = 1$ begins a mathematical paragraph.

#highlighted[#paragraph_tab highlighted text retains its indentation and $a/b$.]

Before#paragraph-tab middle text keeps an inline tab.

This ordinary paragraph has no authored tab.
