# TabletopCompiler

This is a compiler tool for tabletop gaming components - cards, decks, boards, etc.

Needs the following tools:

 * "cp", "rm" for copying tasks, so use Linux or Cygwin/MinGW
 * ImageMagick
 * PhantomJS

Known issues:

 * PhantomJS will not render bold/italic text because of [#13984](https://github.com/ariya/phantomjs/issues/13984). Workaround: use @font-face CSS for bold/italic text.

