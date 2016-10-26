package 
{
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.system.MessageChannel;
    import flash.system.Worker;
    import flash.system.WorkerDomain;
    import flash.text.TextField;
    import flash.utils.ByteArray;
    import flash.utils.getTimer;
    
    [SWF(width="853", height="480", backgroundColor="#ffffff")]
    public class Main extends Sprite 
    {
        private var fpsText:TextField;
        private var streamData:ByteArray = new ByteArray();
        
        // for image display
        private var image:Bitmap;
        private var imageBitmapData:BitmapData;
        private var imageData:ByteArray = new ByteArray();
        private var imageWidth:uint = 0;
        private var imageHeight:uint = 0;
        private var frameCount:uint = 0;
        
        // for decode worker
        protected var decodeWorker:Worker;
        protected var mainToDecodeWorker:MessageChannel;
        protected var decodeWorkerToMain:MessageChannel;

		private var startTime:Number = 0;
        private var i:uint = 0;
        private var baseUrl:String = 'http://cq01-eyun.epc.baidu.com:8087/libde265.js/video/Mad.Max.Fury.Road.2015_x265_832x468_450k_';
        
        public function Main():void
        {
            initUI();
            playBack(baseUrl + (i++ % 10) + '.hevc');
            // playBack('http://cq01-eyun.epc.baidu.com:8087/libde265.js/video/832_480p_wpp.hevc');
        }

        private function playBack(url:String):void {
            var urlRequest:URLRequest = new URLRequest(url);
            var urlLoader:URLLoader = new URLLoader();
            urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
            urlLoader.addEventListener(Event.COMPLETE, loadComplete);
            urlLoader.load(urlRequest);
        }

        private function initUI():void 
        {
            fpsText = new TextField();
            fpsText.width = 60;
            fpsText.height = 15; 
            fpsText.textColor = 0xFFFFFF;
            fpsText.background = true;
            fpsText.backgroundColor = 0x333333;
            fpsText.alpha = 0.8;
            fpsText.mouseEnabled = false;
            fpsText.x = 10;
            fpsText.y = 10;
            addChild(fpsText);
            
            initDecodeWorker();
            return;
        }
        
        private function initDecodeWorker():void
        {
            if (decodeWorker === null) {
                decodeWorker = WorkerDomain.current.createWorker(Workers.DecodeWorker);
            }
            
            // set message channel
            mainToDecodeWorker = Worker.current.createMessageChannel(decodeWorker);             
            decodeWorkerToMain = decodeWorker.createMessageChannel(Worker.current);
            
            // set shared property
            decodeWorker.setSharedProperty("mainToDecodeWorker", mainToDecodeWorker);
            decodeWorker.setSharedProperty("decodeWorkerToMain", decodeWorkerToMain);
            streamData.shareable = true;
            decodeWorker.setSharedProperty("streamData", streamData);
            imageData.shareable = true;
            decodeWorker.setSharedProperty("imageData", imageData);
            
            // listen message from worker
            decodeWorkerToMain.addEventListener(Event.CHANNEL_MESSAGE, onDecodeWorkerToMain, false, 0, true);
            
            // Start worker
            decodeWorker.start();
        }

        private function loadComplete(event:Event):void {
            streamData = event.target.data;
            streamData.shareable = true;
            decodeWorker.setSharedProperty("streamData", streamData);
            mainToDecodeWorker.send(MessageType.START_DECODE);
            return;
        }
                
        private function displayImage():void
        {
            if (image === null || imageBitmapData === null) {
                imageBitmapData = new BitmapData(imageWidth, imageHeight, false, 0x000000);
                image = new Bitmap(imageBitmapData);
                addChild(image);
                setChildIndex(image, 0);
            }
            frameCount++;
            fpsText.text = (frameCount / ((getTimer() - startTime) * 0.001)).toFixed(2) + ' fps';
            if (imageData.length > 0) {
                image.bitmapData.lock();
                imageData.position = 0;
                image.bitmapData.setPixels(imageBitmapData.rect, imageData);
                image.bitmapData.unlock();
            }
        }
        
        // Worker >> Main
        protected function onDecodeWorkerToMain(event:Event):void {
            var messageType:String = decodeWorkerToMain.receive();
            switch (messageType)
            {
                case MessageType.DECODE_START:
                {
					startTime = getTimer();
					frameCount = 0;
                    break;
                }
                    
                case MessageType.FIRST_FRAME:
                {
                    var convertData:Object = decodeWorkerToMain.receive();
                    if (convertData !== null) {
                        if (imageBitmapData == null) {
                            imageWidth = convertData['w'];
                            imageHeight = convertData['h'];
                        }
                    }
                    displayImage();
                    break;
                }
                    
                case MessageType.UNDER_FRAME:
                {
                    displayImage();
                    break;
                }
                    
                case MessageType.DECODE_COMPLETE: {
                    streamData.clear();
                    playBack(baseUrl + (i++ % 10) + '.hevc');
                    // playBack('http://cq01-eyun.epc.baidu.com:8087/libde265.js/video/832_480p_wpp.hevc');
                    break;
                }
                    
                default:
                {
                    break;
                }
            }
        }      
        
    }
    
}