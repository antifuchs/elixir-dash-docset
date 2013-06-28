# Build Elixir docsets for Dash.app

To get started, clone the elixir-lang website repo inside this directory:

    $ git clone git@github.com:elixir-lang/elixir-lang.github.com.git

Then, `bundle install`; and then run (where `0.9.3` is the version of
Elixir whose docs you want to build):

    $ ./build 0.9.3

This will create a .docset bundle, which you can add to Dash.app via:

    $ open -a Dash 'Elixir 0.9.3.docset'


## See also

[Dash.app's docset building reference](http://kapeli.com/docsets)
