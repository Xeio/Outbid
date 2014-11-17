require "Window"
require "CommodityOrder"
require "GameLib"
require "MarketplaceLib"
require "Money"

local Outbid = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("Outbid", true, 
																{ 
																	--"MarketplaceCommodity",
																	--"MarketplaceCREDD",
																	"MarketplaceListings",
																	"Gemini:Logging-1.2"
																	--"Gemini:Locale-1.0",                                                        
																	--"Drafto:Lib:PixiePlot-1.4"
																},
																"Gemini:Hook-1.0"
															)
															
function Outbid:OnInitialize()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("Outbid.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
    logger = GeminiLogging:GetLogger({
        level = GeminiLogging.INFO,
        appender = "GeminiConsole"
    })

	self.orders = nil
	self.orderListWindow = nil

	Apollo.RegisterEventHandler("CommodityInfoResults", "OnCommodityInfoResults", self)
end

-----------------------------------------------------------------------------------------------
-- Outbid OnDocLoaded
-----------------------------------------------------------------------------------------------
function Outbid:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "OutbidForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)


		-- Do additional Addon initialization here
		
		self:Hook(Apollo.GetAddon("MarketplaceListings"), "OnOwnedCommodityOrders")
		self:PostHook(Apollo.GetAddon("MarketplaceListings"), "BuildCommodityOrder")
	end
end

function Outbid:BuildCommodityOrder(luaCaller, nIdx, aucCurrent, wndParent)
	self.orderListWindow = wndParent
	local item = aucCurrent:GetItem()
	--logger:info("Found item listing:" .. item:GetName())
	MarketplaceLib.RequestCommodityInfo(item:GetItemId())
end

function Outbid:OnCommodityInfoResults(nItemId, tStats, tOrders)
	self.stats = tStats
	
	for idx, order in pairs(self.orders) do
		if order:GetItem():GetItemId() == nItemId then
			local orderPrice = order:GetPricePerUnit()
			if order:IsBuy() then
				local topPrice = tStats.arBuyOrderPrices[1].monPrice --Top 1 is first index
				if orderPrice:GetAmount() < topPrice:GetAmount() then					
					local listItemPanel = self.orderListWindow:FindChildByUserData(order)
					local oldButton = listItemPanel:FindChild("RelistBuyButton")
					if oldButton then
						oldButton:Destroy()
					end
					
					local newButton = Apollo.LoadForm(self.xmlDoc, "RelistBuyButton", listItemPanel, self)
					newButton:SetData(order)
					
					local newPrice = Money.new()
					if self:HaveMatchingOrderPrice(nItemId, topPrice) then
						newPrice:SetAmount(topPrice:GetAmount())
					else
						newPrice:SetAmount(topPrice:GetAmount() + 1)
					end
					self:CreateBuyOrder(newButton, nItemId, newPrice, order:GetCount())
				end
			else
				--topPrice = tStats.arSellOrderPrices[1]
			end
		end
	end
end

function Outbid:OnOwnedCommodityOrders(luaCaller, tOrders)
	self.orders = tOrders
end

function Outbid:CreateBuyOrder(button, itemId, price, amount)
	--local orderNew = bBuyTab and CommodityOrder.newBuyOrder(tCurrItem:GetItemId()) or CommodityOrder.newSellOrder(tCurrItem:GetItemId())
	local orderNew = CommodityOrder.newBuyOrder(itemId)
	if price and amount then
		orderNew:SetCount(amount)
		orderNew:SetPrices(price)
		--orderNew:SetForceImmediate(self.wndMain:FindChild("HeaderBuyNowBtn"):IsChecked() or self.wndMain:FindChild("HeaderSellNowBtn"):IsChecked())
	end

	if not orderNew:CanPost() then
		button:Enable(false)
	else
		button:SetActionData(GameLib.CodeEnumConfirmButtonType.MarketplaceCommoditiesSubmit, orderNew)
	end
end

function Outbid:HaveMatchingOrderPrice(itemId, price)
	for idx, order in pairs(self.orders) do
		if order:GetItem():GetItemId() == itemId then
			local orderPrice = order:GetPricePerUnit()
			if orderPrice:GetAmount() == price:GetAmount() then
				return true
			end
		end
	end	
	return false
end

---------------------------------------------------------------------------------------------------
-- RelistBuyButton Functions
---------------------------------------------------------------------------------------------------
function Outbid:RelistBuyClick(wndHandler, wndControl, eMouseButton )
	local order = wndHandler:GetData()
	if not order then
		return
	end
	order:Cancel()
end

function Outbid:SubmittedOrder( wndHandler, wndControl, bSuccess )
	local order = wndHandler:GetData()
	if not order then
		return
	end
	order:Cancel()
end

