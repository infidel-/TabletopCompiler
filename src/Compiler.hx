// compile game.json into a set of images for TTS
// TODO: print game version on all cards
// TODO: print game name somewhere?
// TODO: multiple languages
// TODO: change images

import sys.FileSystem;
import sys.io.File;
import haxe.Json;
import format.csv.Utf8Reader;

class Compiler
{
  var game: _GameConfig;

  public function new()
    {
      game = null;
    }


// run script
  public function run()
    {
      var args = Sys.args();
      if (args.length == 0)
        {
          p('Usage: compiler <game.json>');
          return;
        }

      // read game config
      if (!FileSystem.exists(args[0]))
        {
          p(args[0] + ' does not exist, exiting.');
          return;
        }
      var json = File.getContent(args[0]);
      game = Json.parse(json);

      p('Building game ' + game.name + ' version ' +
        game.version + '...');

      // create temp dirs
      Sys.command('mkdir', [ '-p', 'tmp', 'results' ]);

      var t1 = Sys.time();
      for (t in game.tasks)
        {
          p('Running task ' + t.name + '...');
          var t1 = Sys.time();

          if (t.type == 'deck')
            runTaskDeck(t);
          else if (t.type == 'copy')
            runTaskCopy(t);
          else p("Unknown task type: " + t.type);

          var time = Std.int(Sys.time() - t1);
          p('Task took ' + time + ' seconds.');
        }

      var time = Std.int(Sys.time() - t1);
      p('Build took ' + time + ' seconds.');
    }


// run task: deck
  function runTaskDeck(task: _TaskConfig)
    {
      // cleanup
      runCommand('rm', [ '-f', 'tmp/card*.png' ]);

      p('Reading stats ' + task.stats + '...');
      var statsFile = File.getContent(task.stats);
      p('Reading template ' + task.template + '...');
      var tpl = File.getContent(task.template);

      // parse stats file
      var stats = Utf8Reader.parseCsv(statsFile);

      // find special columns
      var colnames = stats.shift();
      var colAmount = -1;
      for (i in 0...colnames.length)
        if (colnames[i] == '%AMOUNT')
          colAmount = i;

      // generate single card files
      var cardID = 1;
      var numCards = 0;
      for (row in stats)
        {
          var str = tpl;
          for (i in 0...row.length)
            {
              // out of bounds
              if (i >= colnames.length)
                break;

              // skip special columns
              if (i == colAmount)
                continue;

              // TODO: proper language support
              var key = '$' + colnames[i];
              if (key.indexOf('.EN') > 0)
                continue;
              if (key.indexOf('.') > 0)
                key = key.substr(0, key.indexOf('.'));
              var val = row[i];

//              trace(key + ': ' + val);
              str = StringTools.replace(str, key, val);
            }

          // generate HTML file
          // needs to be in the same dir for relative links to work
          File.saveContent('_tmp_card.html', str);

          // render PNG from HTML
          runCommand("phantomjs", [
            'rasterize.js',
            '_tmp_card.html',
            'tmp/card' + cardID + '.png',
            task.cardWidth + 'px*' + task.cardHeight + 'px'
          ]);
          numCards++;

          // if card has amounts
          var amount = Std.parseInt(row[colAmount]);
          if (amount > 1)
            {
              p('Making ' + amount + ' copies...');
              while (amount-- > 1) // -1 for original
                {
                  numCards++;
                  Sys.command('cp', [
                    '-f',
                    'tmp/card' + cardID + '.png',
                    'tmp/card' + cardID +
                      '_copy' + amount + '.png',
                  ]);
                }
            }

          cardID++;
        }
      p('Generated ' + numCards + ' cards');

      // compose deck image
      p('Composing ' + task.result + '...');
      var deckWidth = task.deckWidth;
      if (deckWidth > numCards)
        deckWidth = numCards;
      runCommand('montage', [
        'tmp/card*.png',
        '-geometry', '100%',
        '-tile', deckWidth + 'x',
        'results/' + task.result
      ]);
    }


// run task: copy files
  function runTaskCopy(task: _TaskConfig)
    {
      for (file in task.list)
        runCommand('cp', [
          '-f',
          file,
          "results/",
        ]);
    }


// print and run command
  public inline function runCommand(cmd: String,
      args: Array<String>)
    {
      p(cmd + ' ' + args.join(' '));
      Sys.command(cmd, args);
    }


// print string to console
    public inline function p(s: String)
      {
        Sys.println(s);
      }


  public static function main()
    {
      var c = new Compiler();
      c.run();
    }
}


typedef _GameConfig = {
  var name: String;
  var version: String;
  var tasks: Array<_TaskConfig>;
}


typedef _TaskConfig = {
  var type: String;
  var name: String;
  var result: String;
  var stats: String;
  var lang: Array<String>;
  var template: String;
  var cardWidth: Int;
  var cardHeight: Int;
  var deckWidth: Int;
  var list: Array<String>;
}

