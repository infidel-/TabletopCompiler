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
  var options: _Options;
  var tts: _TTSSave;
  var currentDeckID: Int;
  var resultsDir: String;

  public function new()
    {
      game = null;
      tts = null;
      options = null;
      currentDeckID = 99;
    }


// run script
  public function run()
    {
      var args = Sys.args();
      if (args.length == 0)
        {
          p('Usage: compiler [options] <game.json>');
          p('Command-line options:');
          p('  --tasks <task,...>: run only given tasks (comma-separated)');
          return;
        }

      // parse command-line options
      parseOptions(args);

      // read game config
      if (!FileSystem.exists(options.fileName))
        {
          p(options.fileName + ' does not exist, exiting.');
          return;
        }
      var json = File.getContent(options.fileName);
      game = Json.parse(json);

      var dateStr = DateTools.format(Date.now(), "%Y%m%d-%H%M");
      resultsDir = 'results-' + game.version + '-' + dateStr;

      p('Building game ' + game.name + ' version ' +
        game.version + '...');

      // create temp dirs
      Sys.command('mkdir', [ '-p', 'tmp', resultsDir ]);

      // parse TTS save
//      if (game.tabletopSimulator != null)
        {
          p('Loading Tabletop Simulator template ' +
            game.tabletopSimulator.template + '...');

          var json = File.getContent(game.tabletopSimulator.template);
          tts = Json.parse(json);
        }

      var t0 = Sys.time();
      for (t in game.tasks)
        {
          // only run given tasks
          if (options.tasks != null &&
              !Lambda.has(options.tasks, t.id))
            {
              p('Skipping task ' + t.name + '...');
              continue;
            }

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

      // TTS: fix background
      tts.TableURL = game.tabletopSimulator.prefix +
        resultsDir + '/' + game.tabletopSimulator.tableBackground;

      // save TTS file
      p('Saving TTS file ' + game.tabletopSimulator.result + '...');
      var json = Json.stringify(tts, null, "  ");
      File.saveContent(
        resultsDir + '/' + game.tabletopSimulator.result, json);

      var time = Std.int(Sys.time() - t0);
      p('Build took ' + time + ' seconds.');
    }


// parse command-line options
  function parseOptions(args: Array<String>)
    {
      options = {
        fileName: '',
        tasks: null,
      };

      // assume that last argument is always file name
      options.fileName = args.pop();

      while (args.length > 0)
        {
          var opt = args.shift();

          // tasks list
          if (opt == '--tasks')
            {
              if (args.length == 0)
                {
                  p('Tasks list empty.');
                  Sys.exit(1);
                }

              var str = args.shift();
              options.tasks = str.split(',');
            }
        }

//      trace(options);
    }


// run task: deck
  function runTaskDeck(task: _TaskConfig)
    {
      // cleanup
      runCommand('rm', [ '-f', 'tmp/card*.png' ]);
      currentDeckID++;

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

      // find first card in placeholder deck
      // we will use it as an object template
      var ttsObj: _TTSObject = null;
      var deckName = '$' + task.id;
      for (o in tts.ObjectStates)
        if (o.Nickname == deckName)
          {
            ttsObj = o;
            break;
          }
      if (ttsObj == null)
        {
          p('No placeholder TTS deck for ' + deckName);
          Sys.exit(1);
        }

      // init some common fields
      ttsObj.Name = 'DeckCustom';
      ttsObj.Nickname = task.name;
      ttsObj.DeckIDs = [];
      ttsObj.CustomDeck = {};
      var tplCard = ttsObj.ContainedObjects[0];
      ttsObj.ContainedObjects = [];
      var ttsDeck: _TTSCustomDeck = {
        FaceURL: game.tabletopSimulator.prefix +
          resultsDir + '/' + task.result,
        BackURL: game.tabletopSimulator.prefix +
          resultsDir + '/' + task.back,
        NumWidth: 0,
        NumHeight: 0,
        BackIsHidden: false,
        UniqueBack: false,
      };
      Reflect.setField(ttsObj.CustomDeck, '' + currentDeckID,
        ttsDeck);

/*
      for (f in Reflect.fields(ttsObj))
        trace(f + ': ' + Reflect.field(ttsObj, f));
*/

      // generate single card files
      var cardID = 1;
      var numCards = 0;
      for (row in stats)
        {
          // init TTS card
          var ttsCardID = currentDeckID * 100 + cardID;
          ttsObj.DeckIDs.push(ttsCardID);
          var ttsCard: _TTSCard = Reflect.copy(tplCard);
          ttsCard.CardID = ttsCardID;
          ttsObj.ContainedObjects.push(ttsCard);

          var str = tpl;
          var cardTitle = null;
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
              if (key == "$TITLE")
                cardTitle = val;

//              trace(key + ': ' + val);
              str = StringTools.replace(str, key, val);
            }

          if (cardTitle != null)
            ttsCard.Nickname = cardTitle;

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

          // in non-optimized mode make copies of cards
          if (game.optimizeDecks)
            {
              var amount = Std.parseInt(row[colAmount]);
              while (amount-- > 1) // -1 for original
                {
                  ttsObj.ContainedObjects.push(ttsCard);
                  ttsObj.DeckIDs.push(ttsCardID);
                }
            }
          else
            {
              // if the card has amounts
              // make multiple copies of the same card for
              // simple deck composition
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
            }

          cardID++;
        }
      p('Generated ' + numCards + ' cards');
      var deckWidth = task.deckWidth;
      if (deckWidth > numCards)
        deckWidth = numCards;
      ttsDeck.NumWidth = deckWidth;
      ttsDeck.NumHeight = Std.int(numCards / deckWidth);
//      trace(ttsObj);

      // compose deck image
      p('Composing ' + task.result + '...');
      runCommand('montage', [
        'tmp/card*.png',
        '-geometry', '100%',
        '-tile', deckWidth + 'x',
        resultsDir + '/' + task.result
      ]);
    }


// run task: copy files
  function runTaskCopy(task: _TaskConfig)
    {
      for (file in task.list)
        runCommand('cp', [
          '-f',
          file,
          resultsDir + '/',
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
  var optimizeDecks: Bool;
  var tabletopSimulator: {
    var tableBackground: String;
    var template: String;
    var prefix: String;
    var result: String;
  };
  var tasks: Array<_TaskConfig>;
}


typedef _TaskConfig = {
  var type: String;
  var id: String;
  var name: String;
  var result: String;
  var back: String;
  var stats: String;
  var lang: Array<String>;
  var template: String;
  var cardWidth: Int;
  var cardHeight: Int;
  var deckWidth: Int;
  var list: Array<String>;
}


typedef _Options = {
  var fileName: String;
  var tasks: Array<String>;
}


// partial TTS save file mapping

typedef _TTSSave = {
  var SaveName: String;
  var TableURL: String;
  var ObjectStates: Array<_TTSObject>;
}

typedef _TTSObject = {
  var Name: String;
  var Nickname: String;
  var Description: String;
  var DeckIDs: Array<Int>;
  var CustomDeck: Dynamic;
  var ContainedObjects: Array<_TTSCard>;
  var GUID: String;
}

typedef _TTSCard = {
  var Name: String;
  var Nickname: String;
  var Description: String;
  var CardID: Int;
  var GUID: String;
}


typedef _TTSCustomDeck = {
  var FaceURL: String;
  var BackURL: String;
  var NumWidth: Int;
  var NumHeight: Int;
  var BackIsHidden: Bool;
  var UniqueBack: Bool;
}
