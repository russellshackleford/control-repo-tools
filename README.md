# module dependency checking tools #

There are currently three scripts: `process-puppetfile.rb`,
`search-control-repo.sh`, and `search-component-modules.sh`.

## process-puppetfile.rb ##

`process-puppetfile.rb` will harvest your Puppetfile using the Puppet Forge API
to scrape a module's dependency information. If it is a Git-based module instead
of a Forge module, HTTP(S) will be used to scrape `metadata.json` from the
Git repository. If that fails, it will finally attempt to scrape
`.fixtures.yml`.

### Quick Usage ###

Both `-c|--credentials-file` and `-p|--puppetfile` are optional and will default
to a file called `options` and `Puppetfile` (respectively) in the same directory
as the script itself.

```bash
git clone <URL to this repo>
cd </path/to/this/repo>
bundle install --path .bundle
bundle exec ./process-puppetfile.rb -p </path/to/control-repo/Puppetfile>
```

If you need authentication due to a private repository, basic auth is supported.
A file called `options` in the same directory as the script is the default, but
you can put it pretty much anywhere. Just be careful with permissions!
`.gitignore` is already set to ignore this default file to prevent it being
committed to the repository.

```bash
cat > options <<'EOF'
user: <git host username>
pass: <git host password>
EOF
```

### Dependencies ###
This script was written when using puppet 4. Ruby-2.1.9 is the tested ruby
version (this is the ruby that puppet 4 uses). If that is a system package on
your host then you are done. Otherwise you'll need a ruby version manager like
rbenv or RVM.  This repo is tested with rbenv, but it shouldn't really matter.
You'll additionally need a version of gem that works for the version of ruby you
are using. That should be provided by the system package or by the ruby version
manager. Bundler is optional, but helpful.

* [rbenv](https://github.com/rbenv/rbenv)
* [ruby-build](https://github.com/rbenv/ruby-build)

## search-control-repo.sh ##

### Quick Usage ###

`manifests/site.pp` and all manifests in `site/role/manifests/` will be searched
for any component modules. Each manifest will print which modules it includes
and then a sorted and unique list of all modules called will be printed. Output
is colored (disable with `-c`).

```bash
git clone <URL to this repo>
cd </path/to/this/repo>
./search-control-repo.sh -r <path/to/control-repo> [-c]
```

### Dependencies ###

At the time of writing this, Bash 4 has been released for nearly a decade. If
you use OSX, you will need to figure out how to install an updated Bash.
Additionally, this script assumes a roles layout, not a roles and profiles
layout, which basically means one less layer of abstraction at the cost of a
*possible* (but not overly large) bit of code duplication. This is basically
the same thing as a **super profile** as discussed in [Roles and profiles:
Designing convenient roles](https://puppet.com/docs/pe/2017.2/r_n_p_roles.html)

## search-component-modules.sh ##

### Quick Usage ###

Given a directory with any number of modules installed or cloned, search for all
`.pp` files and look for other modules being called. Currently this does NOT
strip out references to the module itself. That is, searching the `apache`
module will return apache as one of the results.

```bash
git clone <URL to this repo>
cd </path/to/this/repo>
./search-control-repo.sh -r <path/to/a bunch of modules> [-c]
```

### Dependencies ###

Same as `search-control-repo.sh`

[comment]: # ( vim: set tw=80 ts=4 sw=4 sts=4 et: )

