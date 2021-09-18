#property copyright "Copyright 2021, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade/trade.mqh>

/*
//Enum session 
enum Sessions{
   Asian = 0,
   London = 1,
   NewYork = 2,
   ALL = 3,
};
//input Sessions InputSession = ALL;
*/

/******
INPUTS 
******/
input string Risk_Management_Settings = "***RISK MANAGEMENT SETTINGS***";
//closure on opposite signal of indicator
input bool Closure_on_Opposite_Signal = false;
static bool Previous_Trade_is_a_Buy = false; 
static bool Previous_Trade_is_a_Sell = false;
//risk percentage 
input string Percentage_Risk_Settings = "PERCENTAGE RISK SETTINGS";
input bool RiskPercentageSet = false; 
input int RiskPercentage = 2; 
input float TakeProfitBasedOnRiskPercentageRatio = 2.0; //take profit percentage based on the risk percentage, $100 account , risk percentage = 2% , take profit ratio = 2, take profit percentage = 4%
//manual risk management
input string Manual_Risk_Settings = "MANUAL RISK SETTINGS";
input double LotSize = 0.2; 
input double StopLossPoints = 100;
input double TakeProfitPoints = 200;
//atr risk management 
input string ATR_Risk_Settings = "ATR RISK SETTINGS";
input bool ATRStopLoss = false;
input int ATR_StopLoss_Multiple = 1;
input int ATR_Profit_Multiple = 2;
input int ATRPeriod = 14; //default atr period 
//partial take profit 
input string Take_Partial_Settings = "TAKE PARTIAL SETTINGS";
input bool Take_Partial = false;
input int first_take_profit_percent = 75;
input int second_take_profit_percent = 50;
input int first_partial_close_percent = 50;
input int second_partial_close_percent = 75;
input double first_profit = 100;
input double second_profit = 200;
input double first_loss = 100;
input double second_loss = 200;
//trading sessions 
input string Sessions_Settings = "***SESSIONS SETTINGS***";
input bool Trade_on_Asian_Session = true;
input bool Trade_on_London_Session = true;
input bool Trade_on_NewYork_Session = true;
//trading days 
input string Trading_Days_Settings = "***TRADING DAY SETTINGS***";
input bool Trade_on_Monday = true;
input bool Trade_on_Tuesday = true;
input bool Trade_on_Wednesday = true;
input bool Trade_on_Thursday = true;
input bool Trade_on_Friday = true;
//time 
static MqlDateTime CurrentTime; //current time 
//static variables
static bool TimetoTrade = true; //disables or enable the trade execution 
static bool AccureDynasty_Is_Enabled = true; //disables or enables the entire algorithm
//variables 
CTrade trade;
string TradeSignal = "";
static int NextHour;
string CurrencyPair1 = "";
string CurrencyPair2 = "";
string NewsComment = "";
string Type_of_Risk_Management_Used = ""; //set the comment for the type of risk management style used 
string Date_From_News = ""; // on the day itself 
string Date_To_News = ""; //the next day after 

/************
@Brief - the init function for the algo, only runs once at the start 
************/
int OnInit()
  {
   //set chart 
   ChartSetInteger(NULL,CHART_COLOR_CANDLE_BULL,clrLawnGreen);
   ChartSetInteger(NULL,CHART_COLOR_CHART_UP,clrLawnGreen);
   ChartSetInteger(NULL,CHART_COLOR_CANDLE_BEAR,clrOrangeRed);
   ChartSetInteger(NULL,CHART_COLOR_CHART_DOWN,clrOrangeRed);
   ChartSetInteger(NULL,CHART_SHOW_GRID,false); //don't show grid 
   
   //get the currency pairs 
   GetCurrencyPairs();
   
   //set the next hour 
   MqlDateTime InitTime;
   TimeCurrent(InitTime);
   NextHour = InitTime.hour+1;
   
   //set the current day for the news 
   UpdateDayofNews(Date_From_News,Date_To_News);
   
   //Run News Filter Once on Init
   TimeCurrent(CurrentTime);
   NewsFilter(CurrentTime);
   
   //Run Session Filter once on init 
   SessionFilter();
   
   //setting the type of risk management style used
   if(RiskPercentageSet == true){
      Type_of_Risk_Management_Used = " Percentage Risk Mangement";
   }
   else if(ATRStopLoss == true){
      Type_of_Risk_Management_Used = " ATR Risk Management";
   }
   else{
      Type_of_Risk_Management_Used = " Manual Risk Management";
   }
   
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   
  }

/************
@Brief - the on tick function for the algo, runs every tick
************/
void OnTick()
  {
   
   TimeCurrent(CurrentTime); //updating the current time 
   static datetime TimeStamp; //static time stamp
   datetime Time = iTime(_Symbol,PERIOD_CURRENT,0); //Returns the opening time of the bar (indicated by the 'shift' parameter) on the corresponding chart.
   //Debugging 


   //Debugging 
   
   //News Filter 
   if(NextHour == CurrentTime.hour){ 
      //Update the NewsFilter
      NewsFilter(CurrentTime);
      if(NextHour == 23){
         NextHour = 0; //reset the next hour 
      }else{
         NextHour++; //incre next hour 
      }
   }
   
   DayDateFilter();//Day of the week / day filter 
   SessionFilter(); //Session filter 
   
   //if either of the filter encounters a no trade condition
   if(Session_Filter_No_Trading == true || Day_Filter_No_Trade == true){
      AccureDynasty_Is_Enabled = false; //disable the algo 
   }
   
   //Enable the entire Algo 
   if(AccureDynasty_Is_Enabled == true){
      //If Candle Updated 
      if(TimeStamp != Time){
         TimeStamp = Time; //set the time 
         
         //Ask & Bid Price
         double AskPrice = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
         double BidPrice = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
         
         //if time to trade is enabled and the day of the week to not trade is not equal to the current day of the week 
         if(TimetoTrade == true ){
            //trade criteria 
            TradeCriteria();
            //Execute Trade
            ExecuteTrade(AskPrice,BidPrice);
         }
     }//end if for the TimeStamp
   }//end if algo enable 
  
  //Manage Trade 
  TradeManagement();
  
  //Comments
  Comment("Trade Signal : ",TradeSignal,
  "\nDay : ", CurrentTime.day,
  "\nHour of the Day : ", CurrentTime.hour,
  "\nCurrent Time : ", TimeToString(Time),
  "\nCurrent Session : ", Current_Session,
  "\nType of Risk Management :", Type_of_Risk_Management_Used,
  "\nNews Filter : ",NewsComment,
  "\nAlgo Enabled? : ", AccureDynasty_Is_Enabled ? "Yes" : "No");
}//end on tick function

/*******************
@Brief - Manages all open trades 
*******************/
 void TradeManagement(){
    for(int i = PositionsTotal()-1 ; i >= 0 ; i--){
      ulong TicketNumber = PositionGetTicket(i); //get the ticket number of the position
      double PositionProfit = PositionGetDouble(POSITION_PROFIT); //getting the profit of the position 
      //if risk percentage willing to lose is set and the take partial is false
      if(RiskPercentageSet == true && Take_Partial == false){
         double AccountBalance = AccountInfoDouble(ACCOUNT_BALANCE); //account balance 
         double MaximumLoss = 0 - (AccountBalance/100)*RiskPercentage; //maximum loss amount based on the risk percentage on account 
         double MaximumProfit = (AccountBalance/100) * (RiskPercentage * TakeProfitBasedOnRiskPercentageRatio); //maximum take profit level based on the account 
         //if the profit is lesser than the maximum loss, we need to close the position
         if(PositionProfit < MaximumLoss){
            trade.PositionClose(TicketNumber); //close the position
         }
         //if the profit is more than the percentage of the take profit, we also need to close the position
         if(PositionProfit >  MaximumProfit){
            trade.PositionClose(TicketNumber); //close the position
         }
      }else if(RiskPercentageSet == true && Take_Partial == true){
         //do take partial profit and loss and risk percentageset is true 
         double AccountBalance = AccountInfoDouble(ACCOUNT_BALANCE); //account balance 
         double MaximumLoss = 0 - (AccountBalance/100)*RiskPercentage; //maximum loss amount based on the risk percentage on account 
         double MaximumProfit = (AccountBalance/100) * (RiskPercentage * TakeProfitBasedOnRiskPercentageRatio); //maximum take profit level based on the account 
         //if the profit is lesser than the maximum loss, we need to close the position
         if(PositionProfit < MaximumLoss){
            trade.PositionClose(TicketNumber); //close the position
         }
         //if the profit is more than the percentage of the take profit, we also need to close the position
         if(PositionProfit >  MaximumProfit){
            trade.PositionClose(TicketNumber); //close the position
         }
         
         //partial management 
         //PartialManagement();
      }else if(Closure_on_Opposite_Signal == true){
         //do nothing 
      }
      
   }//end for 
 }
 
//trading criteria 
/*******************
@Brief - hold all the trading criteria 
*******************/
void TradeCriteria(){
   //if the position total is 0 

   //news 
   
   /**Strategy to use***/
   //Strategy_MovingAverage();
   //Strategy_BollingerBand();
   Strategy_RSI();

}//end trade criteria function

/*******************
@Brief - Closes all positions 
*******************/
void CloseAllPositions(){
   for(int i = PositionsTotal()-1 ; i >= 0 ; i--){
      ulong TicketNumber = PositionGetTicket(i); //get the ticket number of the position
      double PositionProfit = PositionGetDouble(POSITION_PROFIT); //getting the profit of the position 
      trade.PositionClose(TicketNumber); //closing all positions 
   }
}//end close all positions function


/*******************
@Brief - Executes the trade buy/sell
*******************/
void ExecuteTrade(double AskPrice,double BidPrice){
   //buy or sell 
      if(TradeSignal == "BUY"){
         //if trade stoploss management is by ATR 
         if(ATRStopLoss == true){
            //getting the atr value at the current moment 
            double ATRArray[];
            int ATRHandle = iATR(_Symbol,_Period,ATRPeriod);
            ArraySetAsSeries(ATRArray,true);
            CopyBuffer(ATRHandle,0,0,3,ATRArray);
            double ATRValue = NormalizeDouble(ATRArray[0],_Digits);
            trade.Buy(LotSize,_Symbol,AskPrice,AskPrice-(ATR_StopLoss_Multiple*ATRValue),AskPrice+(ATR_Profit_Multiple*ATRValue)); 
         }
         //risk management based on percentage of account 
         else if(RiskPercentageSet == true){
            //risk will be handled by the trade management function
            trade.Buy(LotSize,_Symbol,AskPrice);
         }
         //closure on opposite signal so we don't add stoploss or takeprofit 
         else if(Closure_on_Opposite_Signal == true){
            //if the previous trade was a buy, you shouldn't execute a seperate sell, you should close the current position 
            if(Previous_Trade_is_a_Sell == true){
               CloseAllPositions(); //close all positions
               Previous_Trade_is_a_Sell = false; //reset 
            }
            else if(PositionsTotal() >= 1){
               //do nothing because there was another trade active 
            }else{
               //will execute a new order
               trade.Buy(LotSize,_Symbol,AskPrice);   
            }
         }
         //manual risk management 
         else{
            //stoploss management manual 
            trade.Buy(LotSize,_Symbol,AskPrice,AskPrice-StopLossPoints*_Point,AskPrice+TakeProfitPoints*_Point); //Buy
         }
         TradeSignal = ""; //reset 
      }else if(TradeSignal == "SELL"){
         //if trade stoploss management is by ATR 
         if(ATRStopLoss == true){
            //getting the atr value at the current moment 
            double ATRArray[];
            int ATRHandle = iATR(_Symbol,_Period,ATRPeriod);
            ArraySetAsSeries(ATRArray,true);
            CopyBuffer(ATRHandle,0,0,3,ATRArray);
            double ATRValue = NormalizeDouble(ATRArray[0],_Digits);
            trade.Sell(LotSize,_Symbol,BidPrice,BidPrice+(ATR_StopLoss_Multiple*ATRValue),BidPrice-(ATR_Profit_Multiple*ATRValue)); 
         }
         //risk management based on percentage of account 
         else if(RiskPercentageSet == true){
            //risk will be handled by the trade management function
            trade.Sell(LotSize,_Symbol,BidPrice);
            //when you execute the trade put the info into the partial trade info 
         }
         //closure on opposite signal so we don't add stoploss or takeprofit 
         else if(Closure_on_Opposite_Signal == true){
            //if the previous trade was a buy, you shouldn't execute a seperate sell, you should close the current position 
            if(Previous_Trade_is_a_Buy == true){
               CloseAllPositions(); //close all positions
               Previous_Trade_is_a_Buy = false; //reset 
            }else if(PositionsTotal() >= 1){
               //do nothing, don't open another trade
            }else{
               //will execute a new order 
               trade.Sell(LotSize,_Symbol,BidPrice);           
            }
         }
         //manual risk management 
         else{
            //stoploss management manual 
            trade.Sell(LotSize,_Symbol,BidPrice,BidPrice+StopLossPoints*_Point,BidPrice-TakeProfitPoints*_Point); //Sell
         }
         TradeSignal = ""; //reset 
      }else{
         //Do Nothing 
      }
}

/*******************
@Brief - Get's the highest candle based on the past number of candles
*******************/
input int NumberofCandlesBreakout = 100;
void BreakOut(){
   //create price array
   MqlRates priceinfo[];
   //sort the array
   ArraySetAsSeries(priceinfo,true);
   //fill the price array with data
   int data = CopyRates(Symbol(),Period(),0,Bars(Symbol(),Period()),priceinfo);
   //calculate number of candles
   int numberofcandles = Bars(Symbol(),Period());
   //calculate the number of candles
   string numberofcandlestext = IntegerToString(numberofcandles);
   //calculate highest and lowest candle number
   int highestcandlenumber = iHighest(NULL,0,MODE_HIGH,NumberofCandlesBreakout,1);
   int lowestcandlenumber = iLowest(NULL,0,MODE_LOW,NumberofCandlesBreakout,1);
   //calculate the highest and lowest price
   double highestprice = priceinfo[highestcandlenumber].high;
   double lowestprice = priceinfo[lowestcandlenumber].low;
   //criteria
   if(priceinfo[0].low < lowestprice){
      //create object
      ObjectCreate(ChartID(),numberofcandlestext,OBJ_ARROW_BUY,0,TimeCurrent(),priceinfo[0].low);
   }
   if(priceinfo[0].high > highestprice){
      //create object
      ObjectCreate(ChartID(),numberofcandlestext,OBJ_ARROW_SELL,0,TimeCurrent(),priceinfo[0].high);
   }
  
}

/*******************
@Brief - Gets the high price trendline to current candle 
*******************/
void Trendline(){
   //get the first visible candle on the chart
   long candleoncahrt = ChartGetInteger(ChartID(),CHART_FIRST_VISIBLE_BAR,0);
   //var for highest candle
   int highestcandle;
   //array
   double high[];
   //set 
   ArraySetAsSeries(high,true);
   //fill array 
   CopyHigh(_Symbol,_Period,0,(int)candleoncahrt,high);
   //calculate the highest candle
   highestcandle = ArrayMaximum(high,0,(int)candleoncahrt);
   //mql rates
   MqlRates priceinfo[];
   //array set
   ArraySetAsSeries(priceinfo,true);
   //copy price 
   int data = CopyRates(_Symbol,_Period,0,(int)candleoncahrt,priceinfo);
   //delete the former line 
   ObjectDelete(ChartID(),"SimpleTrend");
   //create object 
   ObjectCreate(ChartID(),"SimpleTrend",OBJ_TREND,0,priceinfo[highestcandle].time,priceinfo[highestcandle].high,priceinfo[0].time,
   priceinfo[0].high);
   
   //set obj prop
   ObjectSetInteger(0,"SimpleTrend",OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,"SimpleTrend",OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,"SimpleTrend",OBJPROP_RAY_RIGHT,true);   
}
//country codes 
const string EU_Code = "EU";
const string AU_Code = "AU";
const string US_Code = "US";
const string JP_Code = "JP";
const string CH_Code = "CH";
const string NZ_Code = "NZ";
const string GP_Code = "GB";
//trading timings 
input int Hours_of_no_trading_before_after = 2;
const int one_day_in_seconds = (24*60*60);
//static variable 
static bool hit_event = false;

/*******************
@Brief - Filter the news and temporarily stop execution of trade if incoming/outgoing news due to volatility 
*******************/
void NewsFilter(MqlDateTime& CurrTime){
   MqlCalendarValue values[]; 
   
   datetime date_from = StringToTime(Date_From_News) - one_day_in_seconds; //getting today's date as the date from and minus it by 1 day to get new from the day before
   //datetime date_from=D'09.07.2021'; //get all events from this date manual 
   //datetime date_to=0; //0 to get all known events before and after manual 
   datetime date_to= StringToTime(Date_From_News) + one_day_in_seconds; //getting today's date as the date from and adding 1 day in seconds to incre by 1 day 
   
   hit_event = false; //reset the hit event 
   
   Print("For Currency Pair 1 : ",CurrencyPair1);
   //for currency pair 1
   if(CalendarValueHistory(values,date_from,date_to,CurrencyPair1)) 
   { 
      int idx = ArraySize(values)-1;
      while (idx>=0)
      {
         MqlCalendarEvent event; 
         ulong event_id=values[idx].event_id; //set the event id 
         //if there is an event 
         if(CalendarEventById(event_id,event)){
            MqlDateTime TempDateTimeStruct;
            TimeToStruct(values[idx].time,TempDateTimeStruct); //time to mqldatetime struct 
            //if there isn't any event that has been hit, continue looking for events
            if(hit_event == false){
               //checking 2hours before and 2hours after && event importance more than 2 
               if(CurrTime.year == TempDateTimeStruct.year && CurrTime.day_of_year == TempDateTimeStruct.day_of_year && event.importance >= 2) {
                  //within the time period 
                  int test = MathAbs(TempDateTimeStruct.hour - CurrTime.hour);
                  if(MathAbs(TempDateTimeStruct.hour - CurrTime.hour) <= Hours_of_no_trading_before_after || (MathAbs(CurrTime.hour - TempDateTimeStruct.hour) <= Hours_of_no_trading_before_after)){
                     TimetoTrade = false;
                     hit_event = true;
                     NewsComment = "News Incoming or Outgoing! " + event.name + " importance : " + IntegerToString(event.importance) + " Date: " + TimeToString(values[idx].time);
                  }else{
                     TimetoTrade = true; //set original 
                     NewsComment = "No News Incoming or OutGoing!";
                  }
               }else{
                  TimetoTrade = true; //set original
                  NewsComment = "No News Incoming or OutGoing!";
                  
               }
            }
            PrintFormat("%s (%i), Time : %s",event.name,event.importance,TimeToString(values[idx].time)); 
         }
         else 
            PrintFormat("Failed to get event description for event_d=%s, error %d",event_id,GetLastError()); 
         idx--;
      }  
   } 
   else 
   { 
      PrintFormat("Error! Failed to receive events for country_code=%s",CurrencyPair1); 
      PrintFormat("Error code: %d",GetLastError()); 
   }
   Print("For Currency Pair 2 : ", CurrencyPair2);
   //for currency pair 2 
   if(CalendarValueHistory(values,date_from,date_to,CurrencyPair2)) 
   { 
      int idx = ArraySize(values)-1;
      while (idx>=0)
      {
         MqlCalendarEvent event; 
         ulong event_id=values[idx].event_id; //set the event id 
         //if there is an event 
         if(CalendarEventById(event_id,event)){
            MqlDateTime TempDateTimeStruct;
            TimeToStruct(values[idx].time,TempDateTimeStruct); //time to mqldatetime struct
            //if there isn't any event that has been hit, continue looking for events
            if(hit_event == false){             
               //checking 2hours before and 2hours after && event importance more than 2 
               if(CurrTime.year == TempDateTimeStruct.year && CurrTime.day_of_year == TempDateTimeStruct.day_of_year && event.importance >= 2) {
                  //within the time period 
                  if(MathAbs(TempDateTimeStruct.hour - CurrTime.hour) <= Hours_of_no_trading_before_after || (MathAbs(CurrTime.hour - TempDateTimeStruct.hour) <= Hours_of_no_trading_before_after)){
                     TimetoTrade = false;
                     hit_event = true;
                     NewsComment = "News Incoming or Outgoing! " + event.name + " importance : " + IntegerToString(event.importance) + " Date: " + TimeToString(values[idx].time);
                  }else{
                     TimetoTrade = true; //set original 
                     NewsComment = "No News Incoming or OutGoing!";
                  }
               }else{
                  TimetoTrade = true; //set original
                  NewsComment = "No News Incoming or OutGoing!";
               }
            }
            PrintFormat("%s (%i), Time : %s",event.name,event.importance,TimeToString(values[idx].time)); 
         }
         else 
            PrintFormat("Failed to get event description for event_d=%s, error %d",event_id,GetLastError()); 
         idx--;
      }
   } 
   else 
   { 
      PrintFormat("Error! Failed to receive events for country_code=%s",CurrencyPair2); 
      PrintFormat("Error code: %d",GetLastError()); 
   }
}


/*******************
@Brief - For debugging only 
*******************/
template<typename T>
void DebugPrint(T first, T second){
   Print("First Value",first);
   Print("Second Value", second);
}

/*******************
@Brief - Get the currency code based on the string of the currency pair 
*******************/
void GetCurrencyPairs(){
   string TempStringHolder = ChartSymbol(0); //Getting the name of the String; 
   
   //special case for CAD,EUR for Currency Pair 1 
   if(StringSubstr(TempStringHolder,0,2) == "EU"){
      CurrencyPair1 = "EU";
   }else if(StringSubstr(TempStringHolder,0,2) == "CA"){
      CurrencyPair1 = "CAD";
   }else{
      CurrencyPair1 = StringSubstr(TempStringHolder,0,2); //get the name of currency pair 1 
   }
   
   //special case for CAD,EUR for currency pair 2 
   if(StringSubstr(TempStringHolder,3,2) == "EU"){
      CurrencyPair2 = "EU";
   }else if(StringSubstr(TempStringHolder,3,2) == "CA"){
      CurrencyPair2 = "CAD";
   }else{
      CurrencyPair2 = StringSubstr(TempStringHolder,3,2); //get the name of currency pair 2 
   }
}

/*******************
@Brief - Updates the date to be passed into the new filters function 
*******************/
void UpdateDayofNews(string EarlierDate, string LaterDate){
   MqlDateTime TempCurrentTimeStructEarlier;
   MqlDateTime TempCurrentTimeStructLater;
   TimeCurrent(TempCurrentTimeStructEarlier); //get the current time mql style  
   TempCurrentTimeStructLater = TempCurrentTimeStructEarlier; //assign 
   TempCurrentTimeStructLater.day += 1; //incre the day to the next day 
   
   datetime TempCurrentTimeEarlier; //get the date time of the earlier date
   datetime TempCurrentTimeLater; //get the date time of the later date 
   
    //change to date time format 
   TempCurrentTimeEarlier = StructToTime(TempCurrentTimeStructEarlier);
   TempCurrentTimeLater = StructToTime(TempCurrentTimeStructLater); 
   
   //change to string 
   Date_From_News = TimeToString(TempCurrentTimeEarlier);
   Date_To_News = TimeToString(TempCurrentTimeLater);
   
}

/*******************
@Brief - This function filters the day of the week and disables the algo if the day is one of the stated
*******************/
static bool Day_Filter_No_Trade = false;
void DayDateFilter(){
   //filter for the Day of the week 
   //if it's monday and the no trade on monday is true or either of the days set 
   if((MONDAY == CurrentTime.day_of_week && Trade_on_Monday == false) || (TUESDAY == CurrentTime.day_of_week && Trade_on_Tuesday == false) || (WEDNESDAY == CurrentTime.day_of_week && Trade_on_Wednesday == false) || 
   (THURSDAY == CurrentTime.day_of_week && Trade_on_Thursday == false) || (FRIDAY == CurrentTime.day_of_week && Trade_on_Friday == false) ){
      Day_Filter_No_Trade = true; //disable the algo 
   }else{
      Day_Filter_No_Trade = false; //enable the algo 
   }
}



/*******************
@Brief - This function filters session and disables the algo if the session is not active 
*******************/
static string Current_Session = ""; //tracks the current session
static bool Session_Filter_No_Trading = false;
void SessionFilter(){
   /*
      bool  SymbolInfoSessionTrade(
      string            name,                // symbol name
      ENUM_DAY_OF_WEEK  day_of_week,         // day of the week
      uint              session_index,       // session index
      datetime&         from,                // session beginning time
      datetime&         to                   // session end time
      );
   */
   
   /*
      SG Timing - 1500 , ICmarket - 1000 (GMT +2 or GMT +3 when daylight savings is in effect)
      Session timings based on ICMarkets:
      Asian : 0700 SGT -> 0200 ICM
      London : 1500 SGT -> 1000 ICM
      New York :  2000 SGT till 0400 SGT -> 1500 ICM till 2300 ICM
   */
   
   //get the current session
   if(CurrentTime.hour >= 2 && CurrentTime.hour < 10){
      //this is asian session
      Current_Session = "Asian Session";
   }else if(CurrentTime.hour >= 10 && CurrentTime.hour < 15){
      //this is london session
      Current_Session = "London Session";
   }else if(CurrentTime.hour >= 15 && CurrentTime.hour < 23){
      //this is new york session
      Current_Session = "New York Session";
   }else{
      Current_Session = "Invalid Session (Low Activity)";
   }

   //checking with the input sessions
   if((Current_Session == "New York Session" && Trade_on_NewYork_Session == false) || (Current_Session == "Asian Session" && Trade_on_Asian_Session == false) 
   || (Current_Session == "London Session" && Trade_on_London_Session == false)){
      //no trading on either of the sessions 
      Session_Filter_No_Trading = true; //disable the algo 
   }else{
      //enable the algo 
      Session_Filter_No_Trading = false; //enable the algo 
   }
   
}




/*******************
@Brief - This function controls the partial take profit levels and partial close for trade management 
*******************/
void PartialManagement(){
   double balance = AccountInfoDouble(ACCOUNT_BALANCE); //getting the account balance 
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);//getting the account equity
   
   //calculate the lot to close for the profit 
   
   //calculate the lot to close for the loss 
   
   //loop by the entire positions
  for(int i = PositionsTotal() -1 ; i >=0 ; i--){
      ulong positionticket = PositionGetInteger(POSITION_TICKET);//get the ticket number
      
      int positiondirection = (int)PositionGetInteger(POSITION_TYPE); //get the position direction
      //if it is a buy position do take partial profit 
      if(positiondirection == POSITION_TYPE_BUY){
         //if equity is above balance 
         if(balance < (equity+10*_Point)){
            //first partial take profit 
            trade.PositionClosePartial(positionticket,0.01,-1); //close 1 microlot of the position
            //second partial take profit 
         }
         //if equity is below balance do take partial closure 
         if(balance > (equity + 10 * _Point)){
            //first partial closure 
            trade.PositionClosePartial(positionticket,0.01,-1); //close 1 microlot of the position
            //second partial closure 
         }
      }
      //if it is a sell position 
      if(positiondirection == POSITION_TYPE_SELL){
         //if equity is above balance do take partial profit 
         if(balance < (equity + 10 * _Point)){
            //first partial take profit 
            trade.PositionClosePartial(positionticket,0.01,-1);//close 1 microlot of the position
            //second partial take profit 
         }
         //if equity is below balance do take partial closure 
         if(balance >(equity + 10 * _Point)){
            //first partial closure 
            trade.PositionClosePartial(positionticket,0.01,-1);//close 1 microlot of the position
            //second partial take profit 
         }
      }
      
  }

}







/*********************************************** THIS AREA CONTIANS ALL THE VARIOUS STRATEGIES ***********************************************/

/*******************
@Brief - RSI indicator system 
*******************/
input string RSI_Strategy_Settings = "***RSI TRADING STRATEGY SETTINGS***";
input int RSIPeriod = 14;
input bool RSI_Closure_on_Opposite_Signal = true;
void Strategy_RSI(){
   //if there are currently no positions open
   int RSIHandle = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE); //definition 
   double RSIArray[];    //array
   CopyBuffer(RSIHandle,0,1,1,RSIArray); //Set data
   double RSIValue = RSIArray[0]; //RSI Current Value
   
   //Entry Critera 
   if(RSIValue > 30 && RSIValue < 70){
      return;
   }
   if(RSIValue < 30){
      TradeSignal = "BUY";
      //if previous trade is a sell is not true then make it true 
      if(Previous_Trade_is_a_Sell == false){
         Previous_Trade_is_a_Buy = true; //testing
      }
   }
   if(RSIValue > 70){
      TradeSignal = "SELL";
      //if previous trade is a buy is not true then make it true 
      if(Previous_Trade_is_a_Buy == false){
         Previous_Trade_is_a_Sell = true; //testing 
      }
   }   
   

}


/*********************
@Brief - Moving Average Indicator System
*********************/
input string Moving_Average_Strategy_Settings = "***MOVING AVERAGE TRADING STRATEGY SETTINGS***";
input int SlowMA_Period = 200;//period for the slow ma
input int FastMA_Period = 20;//period for the fast ma

void Strategy_MovingAverage(){
         //getting the slow ma 
         static int handleSlowMa = iMA(_Symbol,PERIOD_CURRENT,SlowMA_Period,0,MODE_SMA,PRICE_CLOSE); //using function to pass into the handler 
         double slowMaArray[]; //create an array to store the data 
         CopyBuffer(handleSlowMa,0,1,2,slowMaArray); //copy the data into the buffer
         ArraySetAsSeries(slowMaArray,true); 
         //getting the fast ma 
         static int handleFastMa = iMA(_Symbol,PERIOD_CURRENT,FastMA_Period,0,MODE_SMA,PRICE_CLOSE); //using function to pass into the handler 
         double fastMaArray[]; //create an array to store the data
         CopyBuffer(handleFastMa,0,1,2,fastMaArray); //copy the data into the buffer
         ArraySetAsSeries(fastMaArray,true);
         
         //if the fast moving average cross over the slow moving average, buy
         if(fastMaArray[0] > slowMaArray[0] && fastMaArray[1] < slowMaArray[1]){
            Print("Fast MA is now > than slow ma");
            TradeSignal = "BUY"; //execute a buy 
            //if previous trade is a sell is not true then make it true 
            if(Previous_Trade_is_a_Sell == false){
               Previous_Trade_is_a_Buy = true; //testing
            }
         }
         //if the fast moving average cross over the slow moving average,sell
         if(fastMaArray[0] < slowMaArray[0] && fastMaArray[1] > slowMaArray[1]){
            Print("Slow MA is now > fast ma"); 
            TradeSignal = "SELL"; //execute a sell
            //if previous trade is a buy is not true then make it true 
            if(Previous_Trade_is_a_Buy == false){
               Previous_Trade_is_a_Sell = true; //testing 
            }
         }
}


/************************
@Brief - Moving Average Indicator System with RSI Indicator System
***************************/
//input int SlowMA_Period = 200;//period for the slow ma
//input int FastMA_Period = 20;//period for the fast ma




/*************************
@Brief - Bollinger Band Indicator System 
****************************/
input string Bollinger_Band_Strategy_Settings = "***BOLLINGER BAND TRADING STRATEGY SETTINGS***";
input int bollinger_band_period = 20;
input int bollinger_band_standard_deviation = 2;
void Strategy_BollingerBand(){

      //create an Array for the varous band 
      double MiddleBandArray[];
      double UpperBandArray[];
      double LowerBandArray[];
      //sort the price array from the current candle downwards
      ArraySetAsSeries(MiddleBandArray,true);
      ArraySetAsSeries(UpperBandArray,true);
      ArraySetAsSeries(LowerBandArray,true);
      //define bollinger bands
      int BollingerBandsDefinition = iBands(_Symbol,_Period,bollinger_band_period,0,bollinger_band_standard_deviation,PRICE_CLOSE); //standard deviation
      //copy prices info into the array
      CopyBuffer(BollingerBandsDefinition,0,0,3,MiddleBandArray);
      CopyBuffer(BollingerBandsDefinition,1,0,3,UpperBandArray);
      CopyBuffer(BollingerBandsDefinition,2,0,3,LowerBandArray);
      //calculate EA for the current candle
      double myMiddleBandValue = MiddleBandArray[0];
      double myUpperBandValue = UpperBandArray[0];
      double myLowerBandValue = LowerBandArray[0];
   
      //get the ask price
      double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
      //get the bid price
      double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
      
      //set entry criteria, if ask is below lower bollinger band 
      if(Ask < myLowerBandValue){
         Comment("This is oversold, time to execute a buy! ");
         TradeSignal = "BUY"; //execute a buy 
      }
      
      //set entry criteria, if bid is above the upper bollinger band 
      if(Bid > myUpperBandValue){
         Comment("This is overbought, time to execute a sell! ");
        TradeSignal = "SELL"; //execute a sell
      }
}