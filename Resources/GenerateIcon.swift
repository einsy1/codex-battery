import AppKit
let root = CommandLine.arguments[1]
let iconset = root + "/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let n = size * scale
  let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:n, pixelsHigh:n, bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
  let c = NSGraphicsContext.current!.cgContext
  c.scaleBy(x:CGFloat(n)/1024,y:CGFloat(n)/1024)
  let box = NSBezierPath(roundedRect:NSRect(x:50,y:50,width:924,height:924),xRadius:210,yRadius:210)
  let shadow = NSShadow();shadow.shadowColor = NSColor.black.withAlphaComponent(0.15);shadow.shadowBlurRadius = 25;shadow.shadowOffset = NSSize(width:0,height:-10);shadow.set()
  NSColor(white:0.95,alpha:1).setFill();box.fill()
  NSShadow().set()
  NSGradient(colors:[NSColor(white:1,alpha:1),NSColor(white:0.84,alpha:1)])!.draw(in:box,angle:-90)
  NSColor.white.withAlphaComponent(0.8).setStroke();box.lineWidth=3;box.stroke()
  let shell=NSBezierPath(roundedRect:NSRect(x:200,y:350,width:585,height:324),xRadius:86,yRadius:86)
  NSColor(white:0.25,alpha:0.22).setStroke();shell.lineWidth=14;shell.stroke()
  NSColor(white:0.3,alpha:0.4).setFill();NSBezierPath(roundedRect:NSRect(x:805,y:451,width:26,height:122),xRadius:13,yRadius:13).fill()
  let fill=NSBezierPath(roundedRect:NSRect(x:225,y:375,width:478,height:274),xRadius:62,yRadius:62)
  NSGradient(colors:[NSColor(red:0.28,green:0.85,blue:0.67,alpha:1),NSColor(red:0.04,green:0.61,blue:0.45,alpha:1)])!.draw(in:fill,angle:-80)
  NSColor.white.withAlphaComponent(0.5).setFill();NSBezierPath(roundedRect:NSRect(x:257,y:627,width:407,height:3),xRadius:1.5,yRadius:1.5).fill()
  let string="⌘" as NSString
  let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:156,weight:.medium),.foregroundColor:NSColor.white.withAlphaComponent(0.95)]
  let textSize=string.size(withAttributes:attrs)
  string.draw(at:NSPoint(x:464-textSize.width/2,y:512-textSize.height/2),withAttributes:attrs)
  NSGraphicsContext.restoreGraphicsState()
  let suffix = scale == 2 ? "@2x" : ""
  try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:iconset + "/icon_\(size)x\(size)\(suffix).png"))
 }
}
