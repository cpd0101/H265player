package
{
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.system.MessageChannel;
    import flash.system.Worker;
    import flash.utils.ByteArray;
    import netdisk.libde265.CModule;
    
    public class DecodeWorker extends Sprite
    {
        private var mainToDecodeWorker:MessageChannel;
        private var decodeWorkerToMain:MessageChannel;
        
        private static var DISABLE_DEBLOKING:uint = 1;
        private static var DISABLE_SAO:uint       = 1;
        private static var USE_WPP:Boolean        = true;
        private static var THREAD_NUM:uint        = 2;
        private static var PAGE_SIZE:uint         = 4096;
        
        private var decoder:uint                  = 0;
        private var errorCode:int                 = 0;
        private var errorMsg:String               = 'no error';
        private var frameCount:uint               = 0;
        
        private var streamData:ByteArray = new ByteArray();
        private var imageData:ByteArray = new ByteArray();
        private var imageWidth:uint = 0;
        private var imageHeight:uint = 0;
        private var imageDataLen:uint;
        
        private var more:uint = 0;
        
        public function DecodeWorker()
        {
            CModule.rootSprite = this;
            if(CModule.runningAsWorker()) {
                return;
            }
            CModule.startAsync(this);
            mainToDecodeWorker = Worker.current.getSharedProperty("mainToDecodeWorker");                
            decodeWorkerToMain = Worker.current.getSharedProperty("decodeWorkerToMain");
            
            imageData = Worker.current.getSharedProperty('imageData');
            
            mainToDecodeWorker.addEventListener(Event.CHANNEL_MESSAGE, onMainToDecodeWorker, false, 0, true);
        }
        
        protected function onMainToDecodeWorker(event:Event):void
        {
            var messageType:String = mainToDecodeWorker.receive();
            switch (messageType)
            {
                case MessageType.START_DECODE:
                {
                    streamData = Worker.current.getSharedProperty('streamData');
                    initDecoder();
                    decodeWorkerToMain.send(MessageType.DECODE_START);
                    decode();
                    break;
                }
                    
                default:
                {
                    break;
                }
            }
            
        }
        
        private function initDecoder():void {
            
            // init decoder
            if (decoder === 0) {
                decoder = libde265.de265_new_decoder();
            }

            if (USE_WPP && THREAD_NUM >= 1) {
                errorCode = libde265.de265_start_worker_threads(decoder, THREAD_NUM);
            }
            
            // reset page size
            PAGE_SIZE = 4096;
			
			// disable debloking & sao
			libde265.de265_set_parameter_bool(decoder, libde265.DE265_DECODER_PARAM_DISABLE_DEBLOCKING, DISABLE_DEBLOKING);
			libde265.de265_set_parameter_bool(decoder, libde265.DE265_DECODER_PARAM_DISABLE_SAO, DISABLE_SAO); 
                 
            streamData.position = 0;
            
            more = CModule.malloc(1);
           
            CModule.write8(more, 1);
        }
        
        private function decode():void {
            
            // init param
            var image:ByteArray = new ByteArray();
            
            // read & decode
            while (streamData.bytesAvailable || CModule.read8(more) !== 0) {
                if (PAGE_SIZE > streamData.bytesAvailable) {
                    PAGE_SIZE = streamData.bytesAvailable;  
                }
                // push data
                if (streamData.bytesAvailable == 0) {
                    errorCode = libde265.de265_flush_data(decoder);
                } else {
                    // read buf
                    streamData.readBytes(image, 0, PAGE_SIZE);
                    var imagePtr:uint = CModule.malloc(PAGE_SIZE);
                    CModule.writeBytes(imagePtr, PAGE_SIZE, image);
                    
                    // push data
                    errorCode = libde265.de265_push_data(decoder, imagePtr, PAGE_SIZE, 0);
                    
                    // free tmp data
                    image.clear();
                    CModule.free(imagePtr);                     
                }
                if (!libde265.de265_isOK(errorCode)) {
                    errorMsg = libde265.de265_get_error_text(errorCode);
                    break;
                }
                // decode
                while (CModule.read8(more) !== 0) {
                    // decode
                    errorCode = libde265.de265_decode(decoder, more);
                    if (!libde265.de265_isOK(errorCode)) {                      
                        break;
                    }
                    // get img
                    var img:int = libde265.de265_get_next_picture(decoder);
                    if (img > 0) {
                        if (imageWidth === 0 && imageHeight === 0) {                        
                            imageWidth = libde265.de265_get_image_width(img, 0);
                            imageHeight = libde265.de265_get_image_height(img, 0);
                            imageDataLen = imageWidth * imageHeight * 4;
                        }
                        
                        var argb:uint = CModule.malloc(imageDataLen);
                        libde265.get_display_image(img, imageWidth, imageHeight, argb);
                        imageData.clear();
                        CModule.readBytes(argb, imageDataLen, imageData);
                        CModule.free(argb);
                        img = 0;
                        
                        if (frameCount === 0) {
                            var imageObject:Object = new Object();
                            imageObject['w'] = imageWidth;
                            imageObject['h'] = imageHeight; 

                            decodeWorkerToMain.send(MessageType.FIRST_FRAME);
                            decodeWorkerToMain.send(imageObject);
                            frameCount = 1;
                        } else {
                            decodeWorkerToMain.send(MessageType.UNDER_FRAME);
                        }
						
						break;
                    }
                }
                
                if (errorCode == libde265.DE265_ERROR_WAITING_FOR_INPUT_DATA) {
                    continue;
                }

                if (!libde265.de265_isOK(errorCode)) {
                    CModule.write8(more, 0);
                    break;
                }
                
            }
			
			libde265.de265_free_decoder(decoder);
			decoder = 0;

            decodeWorkerToMain.send(MessageType.DECODE_COMPLETE);
            
        }
        
    }
}