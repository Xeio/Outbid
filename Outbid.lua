require "Window"
require "CommodityOrder"
require "GameLib"
require "MarketplaceLib"
require "Money"

local Outbid = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("Outbid", true, 
	{ 
		"MarketplaceListings",
		"Gemini:Logging-1.2"
	},
	"Gemini:Hook-1.0"
)
															
function Outbid:OnInitialize()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("Outbid.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
    logger = GeminiLogging:GetLogger({
        --level = GeminiLogging.INFO,
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
		self:Hook(Apollo.GetAddon("MarketplaceListings"), "OnOwnedCommodityOrders")
		self:PostHook(Apollo.GetAddon("MarketplaceListings"), "BuildCommodityOrder")
		self:PostHook(Apollo.GetAddon("MarketplaceListings"), "OnToggleFromAuctionHouse")
	end
end

function Outbid:OnToggleFromAuctionHouse(luaCaller)
	local marketplaceListings = Apollo.GetAddon("MarketplaceListings")
	marketplaceListings.wndBtnAuctionListing:SetCheck(false)
	marketplaceListings.wndBtnCommodityListing:SetCheck(true)
end

function Outbid:BuildCommodityOrder(luaCaller, nIdx, aucCurrent, wndParent)
	self.orderListWindow = wndParent:GetParent():GetParent()
	local item = aucCurrent:GetItem()
	MarketplaceLib.RequestCommodityInfo(item:GetItemId())
end

function Outbid:OnCommodityInfoResults(nItemId, tStats, tOrders)
	if not self.orders or not self.orderListWindow or not self.orderListWindow:IsValid() then
		return
	end
	
	if self.oldSellOrder and self.readyToResell then
		if self.oldSellOrder:GetItem():GetItemId() == nItemId then
			local topPrice = tStats.arSellOrderPrices[1].monPrice
			self.sellDialog = Apollo.LoadForm(self.xmlDoc, "ResellConfirm", nil, self)
			local sellButton = self.sellDialog:FindChild("SellButton")
			
			local newPrice = Money.new()
			if self:HaveMatchingOrderPrice(nItemId, topPrice) then
				newPrice:SetAmount(topPrice:GetAmount())
			else
				newPrice:SetAmount(topPrice:GetAmount() - 1)
			end
			
			self:CreateOrderCommand("sell", sellButton, nItemId, newPrice, self.oldSellOrder:GetCount())
			
			self.sellDialog:FindChild("SellText"):SetText(self.oldSellOrder:GetItem():GetName())
			self.sellDialog:FindChild("UnitPrice"):SetAmount(newPrice:GetAmount(), true)
			self.sellDialog:Invoke()
			
			self.oldSellOrder = nil
			self.readyToResell = false
		end
	end

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
					self:CreateOrderCommand("buy", newButton, nItemId, newPrice, order:GetCount())
				end
			else
				local topPrice = tStats.arSellOrderPrices[1].monPrice --Top 1 is first index
				if orderPrice:GetAmount() > topPrice:GetAmount() then					
					local listItemPanel = self.orderListWindow:FindChildByUserData(order)
					local oldButton = listItemPanel:FindChild("RelistSellButton")
					if oldButton then
						oldButton:Destroy()
					end
					
					local newButton = Apollo.LoadForm(self.xmlDoc, "RelistSellButton", listItemPanel, self)
					newButton:SetData(order)
				end
			end
		end
	end
end

function Outbid:OnOwnedCommodityOrders(luaCaller, tOrders)
	self.orders = tOrders
end

function Outbid:CreateOrderCommand(orderType, button, itemId, price, amount)
	local orderNew = orderType == "buy" and CommodityOrder.newBuyOrder(itemId) or CommodityOrder.newSellOrder(itemId)
	if price and amount then
		orderNew:SetCount(amount)
		orderNew:SetPrices(price)
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

function Outbid:SubmittedBuyOrder( wndHandler, wndControl, bSuccess )
	if not bSuccess then
		return
	end
	local order = wndHandler:GetData()
	if not order then
		return
	end
	order:Cancel()
	
	self.oldBuyOrder = order
	self:BuildTimer("BuyMailTimer")
end

function Outbid:RelistSellClick( wndHandler, wndControl, eMouseButton )
	local order = wndHandler:GetData()
	if not order then
		return
	end
	order:Cancel()
	
	self.oldSellOrder = order
	self.readyToResell = false
	self:BuildTimer("SellMailTimer")
end

function Outbid:BuildTimer(timerFunc)
	if self.timer then
		self.timer:Stop()
		self.timer = nil
	end
	self.timer = ApolloTimer.Create(0.2, true, timerFunc, self)
end

function Outbid:BuyMailTimer()
	if not self.oldBuyOrder then
		self.timer:Stop()
	end
	
	--Fetch the money from the cancel mail
	local mails = MailSystemLib.GetInbox()
	local oldItemName = self.oldBuyOrder:GetItem():GetName()
	
	for idx, mail in pairs(mails) do
		local mailInfo = mail:GetMessageInfo()
		local searchPattern = self:GetItemSearchPattern(oldItemName)
		if string.find(mailInfo.strSubject, "Buy") and string.find(mailInfo.strBody, searchPattern) then
			mail:TakeMoney()
			mail:DeleteMessage()
			self.timer:Stop()
			self.oldBuyOrder = nil
			break
		end
	end
end

function Outbid:GetItemSearchPattern(itemName)
	itemName = string.gsub(itemName, "%-", ".") --Dash is special character, replace with dot
	itemName = string.gsub(itemName, "Sign ", "Signs? ") --Possible pluralized word
	return itemName
end

function Outbid:SellMailTimer()
	local mails = MailSystemLib.GetInbox()
	
	if not self.oldSellOrder then
		self.timer:Stop()
	end
	
	local oldItemId = self.oldSellOrder:GetItem():GetItemId()
	
	for idx, mail in pairs(mails) do
		if self:IsItemAttached(mail, oldItemId) then
			mail:TakeAllAttachments()
			mail:DeleteMessage()
			self.timer:Stop()
			self.readyToResell = true
			MarketplaceLib.RequestCommodityInfo(oldItemId) --Re-trigger a market check to relist
			break
		end
	end
end

function Outbid:IsItemAttached(mail, itemId)
	attachements = mail:GetMessageInfo().arAttachments
	for idx, attachment in pairs(attachements) do
		if attachment.itemAttached:GetItemId() == itemId then
			return true
		end
	end
	return false
end

function Outbid:SellCancelClick( wndHandler, wndControl, eMouseButton )
	if self.sellDialog then
        self.sellDialog:Destroy()
        self.sellDialog = nil
    end
end

function Outbid:SellOrderSubmitted( wndHandler, wndControl, bSuccess )
    if self.sellDialog then
        self.sellDialog:Destroy()
        self.sellDialog = nil
    end
end

