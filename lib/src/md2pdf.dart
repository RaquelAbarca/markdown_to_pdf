import 'dart:developer';
import 'dart:io';
import 'dart:mirrors';
import 'package:html/parser.dart';
import 'package:html/dom.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/dart.dart';

// computed style is a stack, each time we encounter an element like <p>... we push its style onto the stack, then pop it off at </p>
// the top of the stack merges all of the styles of the parents.

class ComputedStyle {
  List<Style> stack = [Style()];
  push(Style? s) {
    var base = stack.last;
    s = s ?? Style();
    stack.add(s.merge(base));
  }

  pop() {
    stack.removeLast();
  }

  pw.TextStyle style() {
    return stack.last.style();
  }
}

class _UrlText extends pw.StatelessWidget {
  _UrlText(this.text, this.url);

  final String text;
  final String url;

  @override
  pw.Widget build(pw.Context context) {
    return pw.UrlLink(
      destination: url,
      child: pw.Text(text,
          style: const pw.TextStyle(
            decoration: pw.TextDecoration.underline,
            decorationColor: PdfColors.blue,
            color: PdfColors.blue,
          )),
    );
  }
}

// you will need to add more attributes here, just follow the pattern.
class Style {
  pw.Font? font;
  pw.FontWeight? weight;
  double? height;
  pw.FontStyle? fontStyle;
  pw.UrlLink? urlLink;
  p.PdfColor? color;
  pw.Container? container;
  pw.TextDecoration? textDecoration;
  Style(
      {this.font,
      this.weight,
      this.height,
      this.fontStyle,
      this.color,
      this.container,
      this.textDecoration});

  Style merge(Style s) {
    font ??= s.font;
    weight ??= s.weight;
    height ??= s.height;
    fontStyle ??= s.fontStyle;
    color ??= s.color;
    container ??= s.container;
    textDecoration ??= s.textDecoration;
    return this;
  }

  pw.TextStyle style() {
    return pw.TextStyle(
        font: font,
        fontWeight: weight,
        fontSize: height,
        color: color,
        fontStyle: fontStyle,
        decoration: textDecoration);
  }
}

class BorderStyle {
  const BorderStyle({
    this.paint = true,
    this.pattern,
    this.phase = 0,
  });

  static const none = BorderStyle(paint: false);
  static const solid = BorderStyle();
  static const dashed = BorderStyle(pattern: <int>[3, 3]);
  static const dotted = BorderStyle(pattern: <int>[1, 1]);

  /// Paint this line
  final bool paint;

  /// Lengths of alternating dashes and gaps. The numbers shall be nonnegative
  /// and not all zero.
  final List<num>? pattern;

  /// Specify the distance into the dash pattern at which to start the dash.
  final int phase;
}

// each node is formatted as a chunk. A chunk can be a list of widgets ready to format, or a series of text spans that will be incorporated into a parent widget.
class Chunk {
  List<pw.Widget>? widget;
  pw.TextSpan? text;
  Chunk({this.widget, this.text});
}

// post order traversal of the html tree, recursively format each node.
class Styler {
  var style = ComputedStyle();

  get text => null;

  Chunk formatStyle(Node e, Style s) {
    style.push(s);
    var o = format(e);
    style.pop();
    return o;
  }

  List<pw.Widget> widgetChildren(Node e, Style? s) {
    style.push(s);
    List<pw.Widget> r = [];
    List<pw.TextSpan> spans = [];
    clear() {
      if (spans.isNotEmpty) {
        // turn text into widget
        r.add(pw.RichText(text: pw.TextSpan(children: spans)));
        spans = [];
      }
    }

    for (var o in e.nodes) {
      var ch = format(o);
      if (ch.widget != null) {
        clear();
        r = [...r, ...ch.widget!];
      } else if (ch.text != null) {
        spans.add(ch.text!);
      }
    }
    clear();
    style.pop();
    return r;
  }

  pw.TextSpan inlineChildren(Node e, Style? s, [Style? m]) {
    style.push(s);

    if (m != null) {
      style.push(m);
    }
    List<pw.InlineSpan> r = [];
    for (var o in e.nodes) {
      var ch = format(o);
      if (ch.text != null) {
        r.add(ch.text!);
      }
    }
    style.pop();
    return pw.TextSpan(children: r);
  }

  // I only implmenented necessary ones, but follow the patternZ

  Chunk format(Node e) {
    switch (e.nodeType) {
      case Node.TEXT_NODE:
        return Chunk(
            text: pw.TextSpan(baseline: 0, style: style.style(), text: e.text));
      case Node.ELEMENT_NODE:
        e as Element;
        // for (var o in e.attributes.entries) { o.key; o.value;}
        switch (e.localName) {
          // SPANS
          // spans can contain text or other spans
          case "hr":
            return Chunk(widget: [pw.Divider()]);
          case "li":
            return Chunk(widget: [pw.Bullet(), ...widgetChildren(e, Style())]);
          //case "ol":
          //i++;
          //return Chunk(
          //  widget: [pw.Row(children: widgetChildren(e, Style()))]);
          case "strong":
            return Chunk(
                text: inlineChildren(e, Style(weight: pw.FontWeight.bold)));
          case "blockquote":
            return Chunk(text: inlineChildren(e, Style()));
          case "span":
            return Chunk(text: inlineChildren(e, Style()));
          case "code":

            //   var source = '''main() {
            //   print("Hello, World!");
            // }
            // ''';

            //   highlight.registerLanguage('dart', dart);

            //   var result = highlight.parse(source, language: 'dart');
            //   var html = result.toHtml();
            //   print(html); // HTML string
          
            return Chunk(
                widget: [pw.Wrap(spacing: 5, children: [pw.Container(child: pw.Column(children: widgetChildren(e, Style(font: pw.Font.courier()))),decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                      color: PdfColors.grey200))])]);
          case "pre":
            return Chunk(widget: [
              pw.Container(
                  child: pw.Row(
                      children:
                          widgetChildren(e, Style(font: pw.Font.courier()))),
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                      color: PdfColors.grey200))
            ]);
          case "em":
            return Chunk(
                text: inlineChildren(e, Style(fontStyle: pw.FontStyle.italic)));
          case "del":
            return Chunk(
                text: inlineChildren(e, Style(color: PdfColors.black),
                    Style(textDecoration: pw.TextDecoration.lineThrough)));
          case "a":
            return Chunk(
                widget: [_UrlText((e.innerHtml), (e.attributes["href"]!))]);
          //case "img":
          //return Chunk(widget: [pw.MemoryImage((await rootBundle.load('assets/profile.jpg')).buffer.asUint8List())]);
          // blocks can contain blocks or spans
          case "h1":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 24)));
          case "h2":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 22)));
          case "h3":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 20)));
          case "h4":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 18)));
          case "h5":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 16)));
          case "h6":
            return Chunk(
                widget: widgetChildren(
                    e, Style(weight: pw.FontWeight.bold, height: 14)));
          case "pre":
          case "body":
            return Chunk(widget: widgetChildren(e, Style()));
          case "p":
            return Chunk(widget: widgetChildren(e, Style()));
          default:
            print("${e.localName} is unknown");
            return Chunk(widget: widgetChildren(e, Style()));
        }
      case Node.ENTITY_NODE:
      case Node.ENTITY_REFERENCE_NODE:
      case Node.NOTATION_NODE:
      case Node.PROCESSING_INSTRUCTION_NODE:
      case Node.ATTRIBUTE_NODE:
      case Node.CDATA_SECTION_NODE:
      case Node.COMMENT_NODE:
      case Node.DOCUMENT_FRAGMENT_NODE:
      case Node.DOCUMENT_NODE:
      case Node.DOCUMENT_TYPE_NODE:
        print("${e.nodeType} is unknown node type");
    }
    return Chunk();
  }
}

mdtopdf(String path, String out) async {
  print(Directory.current);
  final md2 = await File(path).readAsString();
  var htmlx = md.markdownToHtml(md2,
      inlineSyntaxes: [md.InlineHtmlSyntax()],
      blockSyntaxes: [
        const md.TableSyntax(),
        md.FencedCodeBlockSyntax(),
        md.HeaderWithIdSyntax(),
        md.SetextHeaderWithIdSyntax(),
      ],
      extensionSet: md.ExtensionSet.gitHubWeb);
  File("$out.html").writeAsString(htmlx);
  var document = parse(htmlx);
  if (document.body == null) {
    return;
  }
  Chunk ch = Styler().format(document.body!);
  var doc = pw.Document();
  doc.addPage(pw.MultiPage(build: (context) => ch.widget ?? []));
  File(out).writeAsBytes(await doc.save());
}
