
include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

ENT.DisableDuplicator = true
ENT.DoNotDuplicate = true

local TYPE_ARROW = 1
local TYPE_ARROWSIDE = 2
local TYPE_DISC = 3

util.AddNetworkString("rgmAxisRequest")
util.AddNetworkString("rgmAxis")

local function SendAxisToPlayer(Axis, pl)

	timer.Simple(0.5, function()
		net.Start("rgmAxis")
			net.WriteEntity(Axis)
			net.WriteEntity(Axis.ArrowX)
			net.WriteEntity(Axis.ArrowY)
			net.WriteEntity(Axis.ArrowZ)
			net.WriteEntity(Axis.ArrowXY)
			net.WriteEntity(Axis.ArrowXZ)
			net.WriteEntity(Axis.ArrowYZ)
			net.WriteEntity(Axis.DiscP)
			net.WriteEntity(Axis.DiscY)
			net.WriteEntity(Axis.DiscR)
			net.WriteEntity(Axis.DiscLarge)
			net.WriteEntity(Axis.ScaleX)
			net.WriteEntity(Axis.ScaleY)
			net.WriteEntity(Axis.ScaleZ)
			net.WriteEntity(Axis.ScaleXY)
			net.WriteEntity(Axis.ScaleXZ)
			net.WriteEntity(Axis.ScaleYZ)
		net.Send(pl)
	end)

end

function ENT:Setup()

	--Arrows
	self.ArrowX = ents.Create("rgm_axis_arrow")
		self.ArrowX:SetParent(self)
		self.ArrowX:Spawn()
		self.ArrowX:SetColor(Color(255,0,0,255))
		self.ArrowX:SetLocalPos(Vector(0,0,0))
		self.ArrowX:SetLocalAngles(Vector(1,0,0):Angle())
		self.ArrowX.axistype = 1

	self.ArrowY = ents.Create("rgm_axis_arrow")
		self.ArrowY:SetParent(self)
		self.ArrowY:Spawn()
		self.ArrowY:SetColor(Color(0,255,0,255))
		self.ArrowY:SetLocalPos(Vector(0,0,0))
		self.ArrowY:SetLocalAngles(Vector(0,1,0):Angle())
		self.ArrowY.axistype = 2

	self.ArrowZ = ents.Create("rgm_axis_arrow")
		self.ArrowZ:SetParent(self)
		self.ArrowZ:Spawn()
		self.ArrowZ:SetColor(Color(0,0,255,255))
		self.ArrowZ:SetLocalPos(Vector(0,0,0))
		self.ArrowZ:SetLocalAngles(Vector(0,0,1):Angle())
		self.ArrowZ.axistype = 3

	--Arrow sides
	self.ArrowXY = ents.Create("rgm_axis_side")
		self.ArrowXY:SetParent(self)
		self.ArrowXY:Spawn()
		self.ArrowXY:SetColor(Color(0,255,0,255))
		self.ArrowXY:SetNWVector("color2",Vector(255,0,0))
		self.ArrowXY:SetNWInt("type",TYPE_ARROWSIDE)
		self.ArrowXY:SetLocalPos(Vector(0,0,0))
		self.ArrowXY:SetLocalAngles(Vector(0,0,-1):Angle())

	self.ArrowXZ = ents.Create("rgm_axis_side")
		self.ArrowXZ:SetParent(self)
		self.ArrowXZ:Spawn()
		self.ArrowXZ:SetColor(Color(255,0,0,255))
		self.ArrowXZ:SetNWVector("color2",Vector(0,0,255))
		self.ArrowXZ:SetNWInt("type",TYPE_ARROWSIDE)
		self.ArrowXZ:SetLocalPos(Vector(0,0,0))
		self.ArrowXZ:SetLocalAngles(Vector(0,-1,0):Angle())

	self.ArrowYZ = ents.Create("rgm_axis_side")
		self.ArrowYZ:SetParent(self)
		self.ArrowYZ:Spawn()
		self.ArrowYZ:SetColor(Color(0,255,0,255))
		self.ArrowYZ:SetNWVector("color2",Vector(0,0,255))
		self.ArrowYZ:SetNWInt("type",TYPE_ARROWSIDE)
		self.ArrowYZ:SetLocalPos(Vector(0,0,0))
		self.ArrowYZ:SetLocalAngles(Vector(1,0,0):Angle())

	--Discs
	self.DiscP = ents.Create("rgm_axis_disc")
		self.DiscP:SetParent(self)
		self.DiscP:Spawn()
		self.DiscP:SetColor(Color(255,0,0,255))
		self.DiscP:SetNWInt("type",TYPE_DISC)
		self.DiscP:SetLocalPos(Vector(0,0,0))
		self.DiscP:SetLocalAngles(Vector(0,1,0):Angle()) -- 0 90 0
		self.DiscP.axistype = 1 -- axistype is a variable to help with setting non physical bones - 1 for pitch, 2 yaw, 3 roll, 4 for the big one

	self.DiscY = ents.Create("rgm_axis_disc")
		self.DiscY:SetParent(self)
		self.DiscY:Spawn()
		self.DiscY:SetColor(Color(0,255,0,255))
		self.DiscY:SetNWInt("type",TYPE_DISC)
		self.DiscY:SetLocalPos(Vector(0,0,0))
		self.DiscY:SetLocalAngles(Vector(0,0,1):Angle()) -- 270 0 0
		self.DiscY.axistype = 2

	self.DiscR = ents.Create("rgm_axis_disc")
		self.DiscR:SetParent(self)
		self.DiscR:Spawn()
		self.DiscR:SetColor(Color(0,0,255,255))
		self.DiscR:SetNWInt("type",TYPE_DISC)
		self.DiscR:SetLocalPos(Vector(0,0,0))
		self.DiscR:SetLocalAngles(Vector(1,0,0):Angle()) -- 0 0 0
		self.DiscR.axistype = 3

	self.DiscLarge = ents.Create("rgm_axis_disc_large")
		self.DiscLarge:SetParent(self)
		self.DiscLarge:Spawn()
		self.DiscLarge:SetColor(Color(175,175,175,255))
		self.DiscLarge:SetNWVector("color2",Vector(88,88,88))
		self.DiscLarge:SetNWInt("type",TYPE_DISC)
		self.DiscLarge:SetLocalPos(Vector(0,0,0))
		self.DiscLarge:SetLocalAngles(Vector(1,0,0):Angle()) --This will be constantly changed
		self.DiscLarge.axistype = 4

	--Scale arrows
	self.ScaleX = ents.Create("rgm_axis_scale_arrow")
		self.ScaleX:SetParent(self)
		self.ScaleX:Spawn()
		self.ScaleX:SetColor(Color(255,0,0,255))
		self.ScaleX:SetLocalPos(Vector(0,0,0))
		self.ScaleX:SetLocalAngles(Vector(1,0,0):Angle())
		self.ScaleX.axistype = 1

	self.ScaleY = ents.Create("rgm_axis_scale_arrow")
		self.ScaleY:SetParent(self)
		self.ScaleY:Spawn()
		self.ScaleY:SetColor(Color(0,255,0,255))
		self.ScaleY:SetLocalPos(Vector(0,0,0))
		self.ScaleY:SetLocalAngles(Vector(0,1,0):Angle())
		self.ScaleY.axistype = 2

	self.ScaleZ = ents.Create("rgm_axis_scale_arrow")
		self.ScaleZ:SetParent(self)
		self.ScaleZ:Spawn()
		self.ScaleZ:SetColor(Color(0,0,255,255))
		self.ScaleZ:SetLocalPos(Vector(0,0,0))
		self.ScaleZ:SetLocalAngles(Vector(0,0,1):Angle())
		self.ScaleZ.axistype = 3

	--Arrow sides
	self.ScaleXY = ents.Create("rgm_axis_scale_side")
		self.ScaleXY:SetParent(self)
		self.ScaleXY:Spawn()
		self.ScaleXY:SetColor(Color(0,255,0,255))
		self.ScaleXY:SetNWVector("color2",Vector(255,0,0))
		self.ScaleXY:SetNWInt("type",TYPE_ARROWSIDE)
		self.ScaleXY:SetLocalPos(Vector(0,0,0))
		self.ScaleXY:SetLocalAngles(Vector(0,0,-1):Angle())

	self.ScaleXZ = ents.Create("rgm_axis_scale_side")
		self.ScaleXZ:SetParent(self)
		self.ScaleXZ:Spawn()
		self.ScaleXZ:SetColor(Color(255,0,0,255))
		self.ScaleXZ:SetNWVector("color2",Vector(0,0,255))
		self.ScaleXZ:SetNWInt("type",TYPE_ARROWSIDE)
		self.ScaleXZ:SetLocalPos(Vector(0,0,0))
		self.ScaleXZ:SetLocalAngles(Vector(0,-1,0):Angle())

	self.ScaleYZ = ents.Create("rgm_axis_scale_side")
		self.ScaleYZ:SetParent(self)
		self.ScaleYZ:Spawn()
		self.ScaleYZ:SetColor(Color(0,255,0,255))
		self.ScaleYZ:SetNWVector("color2",Vector(0,0,255))
		self.ScaleYZ:SetNWInt("type",TYPE_ARROWSIDE)
		self.ScaleYZ:SetLocalPos(Vector(0,0,0))
		self.ScaleYZ:SetLocalAngles(Vector(1,0,0):Angle())

	self.Axises = {
		self.ArrowX,
		self.ArrowY,
		self.ArrowZ,
		self.ArrowXY,
		self.ArrowXZ,
		self.ArrowYZ,
		self.DiscP,
		self.DiscY,
		self.DiscR,
		self.DiscLarge,
		self.ScaleX,
		self.ScaleY,
		self.ScaleZ,
		self.ScaleXY,
		self.ScaleXZ,
		self.ScaleYZ,
	}

	SendAxisToPlayer(self, self.Owner)

end

net.Receive("rgmAxisRequest", function(len, pl)
	timer.Simple(0.5, function()

	local Axis = pl.rgm.Axis

	if not Axis.Axises then
		Axis:Setup()
	end

	SendAxisToPlayer(Axis, pl)

	end)
end)

function ENT:Think()
	local pl = self.Owner
	if not IsValid(pl) then return end

	local ent = pl.rgm.Entity
	local bone = pl.rgm.PhysBone
	if not IsValid(ent) or not pl.rgm.Bone or not self.Axises then return end

	local pos, ang
	local rotate = pl.rgm.Rotate or false
	local scale = pl.rgm.Scale or false
	local offset, offsetlocal = pl.rgm.GizmoOffset, self.localizedoffset

	if IsValid(ent:GetParent()) and pl.rgm.Bone == 0 and not ent:IsEffectActive(EF_BONEMERGE) and not (ent:GetClass() == "prop_ragdoll") then
		pos = ent:GetParent():LocalToWorld(ent:GetLocalPos())
	elseif pl.rgm.IsPhysBone then

		local physobj = ent:GetPhysicsObjectNum(bone)
		if physobj == nil then return end
		pos = physobj:GetPos()

	else
		bone = pl.rgm.Bone
		if not pl.rgm.GizmoPos then
			local matrix = ent:GetBoneMatrix(bone)
			pos = ent:GetBonePosition(bone)
			if pos == ent:GetPos() then
				pos = matrix:GetTranslation()
			end
		else
			pos = pl.rgm.GizmoPos
		end
	end
	if IsValid(ent:GetParent()) and pl.rgm.Bone == 0 and not ent:IsEffectActive(EF_BONEMERGE) and not (ent:GetClass() == "prop_ragdoll") and not scale then
		ang = ent:GetParent():LocalToWorldAngles(ent:GetLocalAngles())
	elseif pl.rgm.IsPhysBone and not scale then

		local physobj = ent:GetPhysicsObjectNum(bone)
		if physobj == nil then return end
		ang = physobj:GetAngles()

	else
		if rotate then
			if ent:GetBoneParent(bone) ~= -1 then
				if not pl.rgm.GizmoParent then -- dunno if there is a need for these failsafes
					_ , ang = ent:GetBonePosition(bone)
				else
					_ , pang = ent:GetBonePosition(ent:GetBoneParent(bone))
					_ , ang = ent:GetBonePosition(bone)
					ang = pl.rgm.GizmoParent - pang + ang
				end
			else
				_ , ang = ent:GetBonePosition(bone)
			end
		elseif scale and pl.rgm.GizmoAng then
			ang = pl.rgm.GizmoAng
		else
			if ent:GetBoneParent(bone) ~= -1 then
				if not pl.rgm.GizmoParent then
					local matrix = ent:GetBoneMatrix(ent:GetBoneParent(bone)) -- never would have guessed that when moving bones they use angles of their parent bone rather than their own angles. happened to get to know that after looking at vanilla bone manipulator!
					ang = matrix:GetAngles()
				else
					ang = pl.rgm.GizmoParent
				end
			else
				if IsValid(ent) then
					ang = ent:GetAngles()
				end
			end
		end
	end

	if not pl.rgm.Moving or not rotate then
		if offsetlocal then 
			self:SetPos(LocalToWorld(offset, Angle(0, 0, 0), pos, ang))
		else
			self:SetPos(pos + offset)
		end
	end

	local localstate = self.localizedpos
	if rotate then 
		localstate = self.localizedang
	end

	if not pl.rgm.Moving then -- Prevent whole thing from rotating when we do localized rotation - needed for proper angle reading
		if localstate or scale or not pl.rgm.IsPhysBone then -- Non phys bones don't go well with world coordinates. Well, I didn't make them to behave with those
			self:SetAngles(ang or Angle(0,0,0))
			if (ent:GetClass() == "prop_ragdoll" or ent:GetClass() == "prop_dynamic" or ent:GetClass() == "ent_bonemerged") and (not pl.rgm.IsPhysBone) then
				self.DiscP:SetLocalAngles(Angle(0, 90 + ent:GetManipulateBoneAngles(bone).y, 0)) -- Pitch follows Yaw angles
				self.DiscR:SetLocalAngles(Angle(0 + ent:GetManipulateBoneAngles(bone).x, 0 + ent:GetManipulateBoneAngles(bone).y, 0)) -- Roll follows Pitch and Yaw angles
			else
				self.DiscP:SetLocalAngles(Angle(0, 90, 0))
				self.DiscR:SetLocalAngles(Angle(0, 0, 0))
			end
		else
			self:SetAngles(Angle(0,0,0))
			self.DiscP:SetLocalAngles(Angle(0, 90, 0))
			self.DiscR:SetLocalAngles(Angle(0, 0, 0))
		end
		self.LocalAngles = ang
		self.BonePos = pos
	end

	local pos, poseye = self:GetPos(), pl:EyePos()
	local disc = self.DiscLarge
	local ang = (pos - poseye):Angle()
	ang = self:WorldToLocalAngles(ang)
	disc:SetLocalAngles(ang)

	pos, poseye = self:WorldToLocal(pos), self:WorldToLocal(poseye)
	local xangle, yangle = (Vector(pos.y, pos.z, 0) - Vector(poseye.y, poseye.z, 0)):Angle(), (Vector(pos.x, pos.z, 0) - Vector(poseye.x, poseye.z, 0)):Angle()
	local XAng, YAng, ZAng = Angle(0, 0, xangle.y + 90) + Vector(1,0,0):Angle(), Angle(0, 90, 90) - Angle(0,0,yangle.y), Angle(0, ang.y, 0) + Vector(0,0,1):Angle()
	self.ArrowX:SetLocalAngles(XAng)
	self.ScaleX:SetLocalAngles(XAng)
	self.ArrowY:SetLocalAngles(YAng)
	self.ScaleY:SetLocalAngles(YAng)
	self.ArrowZ:SetLocalAngles(ZAng)
	self.ScaleZ:SetLocalAngles(ZAng)

	self:NextThink(CurTime()+0.001)
	return true
end
