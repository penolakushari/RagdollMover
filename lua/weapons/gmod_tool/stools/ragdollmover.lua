
TOOL.Name = "#tool.ragdollmover.name"
TOOL.Category = "Poser"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["localpos"] = 0
TOOL.ClientConVar["localang"] = 1
TOOL.ClientConVar["localoffset"] = 1
TOOL.ClientConVar["relativerotate"] = 0
TOOL.ClientConVar["scale"] = 10
TOOL.ClientConVar["width"] = 0.5
TOOL.ClientConVar["fulldisc"] = 0
TOOL.ClientConVar["disablefilter"] = 0
TOOL.ClientConVar["lockselected"] = 0
TOOL.ClientConVar["scalechildren"] = 0
TOOL.ClientConVar["smovechildren"] = 0
TOOL.ClientConVar["physmove"] = 0
TOOL.ClientConVar["drawskeleton"] = 0
TOOL.ClientConVar["snapenable"] = 0
TOOL.ClientConVar["snapamount"] = 30

TOOL.ClientConVar["ik_leg_L"] = 0
TOOL.ClientConVar["ik_leg_R"] = 0
TOOL.ClientConVar["ik_hand_L"] = 0
TOOL.ClientConVar["ik_hand_R"] = 0
TOOL.ClientConVar["ik_chain_1"] = 0
TOOL.ClientConVar["ik_chain_2"] = 0
TOOL.ClientConVar["ik_chain_3"] = 0
TOOL.ClientConVar["ik_chain_4"] = 0
TOOL.ClientConVar["ik_chain_5"] = 0
TOOL.ClientConVar["ik_chain_6"] = 0
TOOL.ClientConVar["hipkneeroll"] = 3
TOOL.ClientConVar["ignoredaxis"] = 3

TOOL.ClientConVar["unfreeze"] = 0
TOOL.ClientConVar["updaterate"] = 0.01

TOOL.ClientConVar["rotatebutton"] = MOUSE_MIDDLE
TOOL.ClientConVar["scalebutton"] = MOUSE_RIGHT

local ConstrainedAllowed

local BONELOCK_FAILED = 0
local BONELOCK_SUCCESS = 1
local BONELOCK_FAILED_NOTPHYS = 2
local BONELOCK_FAILED_SAME = 3
local ENTLOCK_FAILED_NONPHYS = 4
local ENTLOCK_FAILED_NOTALLOWED = 5
local ENTLOCK_SUCCESS = 6
local ENTSELECT_LOCKRESPONSE = 20
local BONE_FROZEN = 7
local BONE_UNFROZEN = 8

local VECTOR_SCALEDEF = Vector(1, 1, 1)

local function rgmGetBone(pl, ent, bone)
	--------------------------------------------------------- yeah this part is from locrotscale
	local phys, physobj
	pl.rgm.IsPhysBone = false

	local count = ent:GetPhysicsObjectCount()
	local isragdoll = ent:GetClass() == "prop_ragdoll"
	local physbones = {}

	for i = 0, count - 1 do
		local b = ent:TranslatePhysBoneToBone(i)
		if bone == b then 
			phys = i
			pl.rgm.IsPhysBone = true
		end
		physbones[b] = i
	end

	if count == 1 then
		if not isragdoll and bone == 0 then
			phys = 0
			pl.rgm.IsPhysBone = true
		end
	end
	---------------------------------------------------------
	local bonen = phys or bone

	pl.rgm.PhysBone = bonen
	if isragdoll then -- physics props only have 1 phys object which is tied to bone -1, and that bone doesn't really exist
		if pl.rgm.IsPhysBone then
			pl.rgm.Bone = ent:TranslatePhysBoneToBone(bonen)
			pl.rgm.NextPhysBone = nil
			pl.rgmPhysMove = {} -- bones for the nonphysics moving thing
		else
			pl.rgm.Bone = bonen
			pl.rgmPhysMove = {}

			local function FindPhysBone(boneid, ent)
				local parent = ent:GetBoneParent(boneid)
				if parent == -1 then
					return nil
				else
					if physbones[parent] then
						return physbones[parent]
					else
						return FindPhysBone(parent, ent)
					end
				end
			end

			local function GetUsedBones(bone, ent, depth)
				for _, cbone in ipairs(ent:GetChildBones(bone)) do
					local add = 0
					if physbones[cbone] then
						local phys = physbones[cbone]
						add = 1
						pl.rgmPhysMove[phys] = {}
						pl.rgmPhysMove[phys].bone = cbone
						pl.rgmPhysMove[phys].depth = depth
					end
					GetUsedBones(cbone, ent, depth + add)
				end
			end
			pl.rgm.NextPhysBone = FindPhysBone(bonen, ent)
			GetUsedBones(bonen, ent, 1)
		end
	else
		pl.rgm.Bone = bonen
		pl.rgm.NextPhysBone = nil
		pl.rgmPhysMove = {}
	end
end

local function rgmCanTool(ent, pl)
	local cantool

	if CPPI and ent.CPPICanTool then
		cantool = ent:CPPICanTool(pl, "ragdollmover")
	else
		cantool = true
	end

	return cantool
end

local function rgmFindEntityChildren(parent)
	local children = {}

	local function RecursiveFindChildren(entity)
		for k, ent in pairs(entity:GetChildren()) do
			if not IsValid(ent) or ent:IsWorld() or ent:IsConstraint() or not isstring(ent:GetModel()) or not util.IsValidModel(ent:GetModel()) then continue end

			table.insert(children, ent)
			RecursiveFindChildren(ent)
		end
	end

	RecursiveFindChildren(parent)

	return children
end

local function rgmGetConstrainedEntities(parent)
	local conents = constraint.GetAllConstrainedEntities(parent)
	local children = {}

	conents[parent] = nil
	if parent.rgmPRidtoent then
		for k, ent in pairs(parent.rgmPRidtoent) do
			conents[ent] = nil
		end
	end

	if parent:GetParent() then
		conents[parent:GetParent()] = nil
	end

	local count = 1

	for _, ent in pairs(conents) do

		if not IsValid(ent) or ent:IsWorld() or ent:IsConstraint() or not util.IsValidModel(ent:GetModel()) or IsValid(ent:GetParent()) then continue end
		if ent:GetPhysicsObjectCount() > 0 then
			children[count] = ent
			count = count + 1
		end
	end

	return children
end

local function rgmCalcGizmoPos(pl)
	if not pl.rgm or not pl.rgm.GizmoAng then return end
	local axis, entog = pl.rgm.Axis, pl.rgm.Entity
	local ent = entog

	local bone = pl.rgm.Bone

	if axis.EntAdvMerged then
		ent = ent:GetParent()
		if ent.AttachedEntity then ent = ent.AttachedEntity end
	end

	axis.GizmoAng = pl.rgm.GizmoAng

	local ppos, pang = pl.rgm.GizmoPParent, pl.rgm.GizmoParent

	if not (axis.EntAdvMerged) then
		local manang = entog:GetManipulateBoneAngles(bone)
		manang:Normalize()

		_, axis.GizmoAng = LocalToWorld(vector_origin, Angle(0, manang[2], 0), vector_origin, axis.GizmoAng)
		_, axis.GizmoAng = LocalToWorld(vector_origin, Angle(manang[1], 0, 0), vector_origin, axis.GizmoAng)
		_, axis.GizmoAng = LocalToWorld(vector_origin, Angle(0, 0, manang[3]), vector_origin, axis.GizmoAng)
	end

	local nonpos
	if pl.rgm.GizmoParentID ~= -1 then
		local physobj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
		if not physobj then return end
		ppos, pang = LocalToWorld(ppos, pang, physobj:GetPos(), physobj:GetAngles())
		nonpos = LocalToWorld(entog:GetManipulateBonePosition(bone), angle_zero, ppos, pang)
		nonpos = WorldToLocal(nonpos, pang, physobj:GetPos(), physobj:GetAngles())
	else
		ppos, pang = LocalToWorld(ppos, pang, ent:GetPos(), ent:GetAngles())
		nonpos = LocalToWorld(entog:GetManipulateBonePosition(bone), angle_zero, ppos, pang)
		nonpos = WorldToLocal(nonpos, pang, ent:GetPos(), ent:GetAngles())
	end

	axis.GizmoPos = pl.rgm.GizmoPos + nonpos
end

local function rgmAdjustScaleTable(parent, childbones, ppos, pang)
	if not childbones[parent] then return end
	for bone, tab in pairs(childbones[parent]) do
		local wpos, wang = LocalToWorld(tab.pos, tab.ang, ppos, pang)
		tab.wpos = wpos
		rgmAdjustScaleTable(bone, childbones, wpos, wang)
	end
end

if SERVER then

util.AddNetworkString("rgmUpdateLists")

util.AddNetworkString("rgmUpdateEntInfo")

util.AddNetworkString("rgmAskForPhysbones")
util.AddNetworkString("rgmAskForPhysbonesResponse")
util.AddNetworkString("rgmAskForNodeUpdatePhysics")
util.AddNetworkString("rgmAskForNodeUpdatePhysicsResponse")

util.AddNetworkString("rgmAskForParented")
util.AddNetworkString("rgmAskForParentedResponse")

util.AddNetworkString("rgmSelectBone")
util.AddNetworkString("rgmSelectBoneResponse")

util.AddNetworkString("rgmLockBone")
util.AddNetworkString("rgmLockBoneResponse")
util.AddNetworkString("rgmLockToBone")
util.AddNetworkString("rgmLockToBoneResponse")
util.AddNetworkString("rgmUnlockToBone")
util.AddNetworkString("rgmUnlockToBoneResponse")
util.AddNetworkString("rgmLockConstrained")
util.AddNetworkString("rgmLockConstrainedResponse")
util.AddNetworkString("rgmUnlockConstrained")
util.AddNetworkString("rgmBoneFreezer")

util.AddNetworkString("rgmSelectEntity")
util.AddNetworkString("rgmSendBonePos")
util.AddNetworkString("rgmRequestBonePos")

util.AddNetworkString("rgmPrepareOffsets")
util.AddNetworkString("rgmClearOffsets")

util.AddNetworkString("rgmResetGizmo")
util.AddNetworkString("rgmOperationSwitch")
util.AddNetworkString("rgmSetGizmoToBone")
util.AddNetworkString("rgmUpdateGizmo")

util.AddNetworkString("rgmResetAllBones")
util.AddNetworkString("rgmResetAll")
util.AddNetworkString("rgmResetPos")
util.AddNetworkString("rgmResetAng")
util.AddNetworkString("rgmResetScale")
util.AddNetworkString("rgmScaleZero")
util.AddNetworkString("rgmAdjustBone")
util.AddNetworkString("rgmGizmoOffset")

util.AddNetworkString("rgmDeselectEntity")
util.AddNetworkString("rgmUpdateSliders")
util.AddNetworkString("rgmUpdateCCVar")

util.AddNetworkString("rgmNotification")

ConstrainedAllowed = CreateConVar("sv_ragdollmover_allow_constrained_locking", 1, FCVAR_ARCHIVE + FCVAR_NOTIFY, "Allow usage of locking constrained entities to Ragdoll Mover's selected entity (Can be abused by attempting to move a lot of entities)", 0, 1)

net.Receive("rgmAskForPhysbones", function(len, pl)
	local entcount = net.ReadUInt(13)
	local ents = {}
	local cancel

	for i = 1, entcount do
		ents[i] = net.ReadEntity()
		if not rgmCanTool(ents[i], pl) then cancel = true end
	end

	if cancel then return end

	if not next(ents) then return end
	local sendents = {}

	for i, ent in ipairs(ents) do
		if not IsValid(ent) then continue end
		local count = ent:GetPhysicsObjectCount() - 1
		if count ~= -1 then
			table.insert(sendents, ent)
		end
	end

	net.Start("rgmAskForPhysbonesResponse")
		net.WriteUInt(#sendents, 13)
		for _, ent in ipairs(sendents) do
			net.WriteEntity(ent)

			local count = ent:GetPhysicsObjectCount() - 1
			net.WriteUInt(count, 8)
			for i = 0, count do
				local bone = ent:TranslatePhysBoneToBone(i)
				if bone == -1 then bone = 0 end
				local poslock = pl.rgmPosLocks[ent] and pl.rgmPosLocks[ent][i] or nil
				local anglock = pl.rgmAngLocks[ent] and pl.rgmAngLocks[ent][i] or nil
				local bonelock = pl.rgmBoneLocks[ent] and pl.rgmBoneLocks[ent][i] or nil

				net.WriteUInt(bone, 8)
				net.WriteBool(poslock ~= nil)
				net.WriteBool(anglock ~= nil)
				net.WriteBool(bonelock ~= nil)
			end
		end
	net.Send(pl)
end)

net.Receive("rgmAskForNodeUpdatePhysics", function(len, pl)
	local isphys = net.ReadBool()
	local entcount = net.ReadUInt(13)
	local reents, ents = {}, {}
	local cancel

	for i = 1, entcount do
		reents[i] = net.ReadEntity()
		if not rgmCanTool(reents[i], pl) then cancel = true end
	end

	if cancel then return end

	local validcount = 0
	for i, ent in ipairs(reents) do
		if not IsValid(ent) then continue end
		validcount = validcount + 1
		ents[validcount] = ent
	end

	if not next(ents) then return end

	net.Start("rgmAskForNodeUpdatePhysicsResponse")
		net.WriteBool(isphys)
		net.WriteUInt(validcount, 13)
		for i, ent in ipairs(ents) do
			net.WriteEntity(ent)

			local count = ent:GetPhysicsObjectCount()
			net.WriteUInt(count, 8)
			if count ~= 0 then
				for i = 0, count - 1 do
					local bone = ent:TranslatePhysBoneToBone(i)
					if bone == -1 then bone = 0 end
					net.WriteUInt(bone, 8)
				end
			end

		end
	net.Send(pl)
end)

net.Receive("rgmAskForParented", function(len, pl)
	local entcount = net.ReadUInt(13)
	local ents = {}
	local cancel

	for i = 1, entcount do
		ents[i] = net.ReadEntity()
		if not rgmCanTool(ents[i], pl) then cancel = true end
	end

	if cancel then return end

	local parented = {}
	local pcount = 0

	for _, ent in ipairs(ents) do
		if not IsValid(ent) or not IsValid(ent:GetParent()) then continue end

		parented[ent] = {}
		pcount = pcount + 1

		if ent:GetClass() ~= "ent_advbonemerge" then
			for i = 0, ent:GetBoneCount() - 1 do
				if ent:GetParent():LookupBone(ent:GetBoneName(i)) then
					table.insert(parented[ent], i)
				end
			end
		else
			local advbones = ent.AdvBone_BoneInfo

			if advbones and next(advbones) then
				for i = 0, ent:GetBoneCount() - 1 do
					if advbones[i].parent ~= "" then
						table.insert(parented[ent], i)
					end
				end
			end
		end
	end

	if next(parented) then
		net.Start("rgmAskForParentedResponse")
			net.WriteUInt(pcount, 13)
			for ent, bones in pairs(parented) do
				net.WriteEntity(ent)
				net.WriteUInt(#bones, 10)
				for k, id in ipairs(bones) do
					net.WriteUInt(id, 10)
				end
			end
		net.Send(pl)
	end
end)

net.Receive("rgmSelectBone", function(len, pl)
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(10)

	if not rgmCanTool(ent, pl) then return end

	pl.rgm.BoneToResetTo = (ent:GetClass() == "prop_ragdoll") and ent:TranslatePhysBoneToBone(0) or 0
	pl.rgm.Entity = ent
	pl.rgm.Axis.EntAdvMerged = false
	rgmGetBone(pl, ent, bone)
	pl:rgmSync()

	net.Start("rgmSelectBoneResponse")
		net.WriteBool(pl.rgm.IsPhysBone)
		net.WriteEntity(ent)
		net.WriteUInt(pl.rgm.Bone, 10)
	net.Send(pl)
end)

net.Receive("rgmLockBone", function(len, pl)
	local ent = net.ReadEntity()
	local mode = net.ReadUInt(2)
	local bone = net.ReadUInt(10)
	local physbone = bone
	local boneid

	if not rgmCanTool(ent, pl) then return end
	if not IsValid(ent) or ent:TranslateBoneToPhysBone(physbone) == -1 then return end
	if ent:GetClass() ~= "prop_ragdoll" and not ent.rgmPRenttoid and mode ~= 3 then return end

	if ent:GetClass() == "prop_ragdoll" then
		physbone = rgm.BoneToPhysBone(ent, bone)
		boneid = physbone
	elseif ent.rgmPRenttoid then
		boneid = ent.rgmPRenttoid[ent]
	end

	if mode == 1 then
		if not pl.rgmPosLocks[ent][boneid] then
			pl.rgmPosLocks[ent][boneid] = ent:GetPhysicsObjectNum(physbone)
		else
			pl.rgmPosLocks[ent][boneid] = nil
		end
	elseif mode == 2 then
		if not pl.rgmAngLocks[ent][boneid] then
			pl.rgmAngLocks[ent][boneid] = ent:GetPhysicsObjectNum(physbone)
		else
			pl.rgmAngLocks[ent][boneid] = nil
		end
	elseif mode == 3 then
		if not pl.rgmScaleLocks[ent][bone] then
			pl.rgmScaleLocks[ent][bone] = true
		else
			pl.rgmScaleLocks[ent][bone] = false
		end
	end

	local poslock, anglock, scllock = IsValid(pl.rgmPosLocks[ent][boneid]), IsValid(pl.rgmAngLocks[ent][boneid]), pl.rgmScaleLocks[ent][bone]

	net.Start("rgmLockBoneResponse")
		net.WriteEntity(ent)
		net.WriteUInt(bone, 10)
		net.WriteBool(poslock)
		net.WriteBool(anglock)
		net.WriteBool(scllock)
	net.Send(pl)
end)

net.Receive("rgmBoneFreezer", function(len, pl)
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(10)
	local boneid

	if not rgmCanTool(ent, pl) then return end
	if not IsValid(ent) or ent:TranslateBoneToPhysBone(bone) == -1 then return end

	if ent:GetClass() == "prop_ragdoll" then
		boneid = rgm.BoneToPhysBone(ent, bone)
	else
		boneid = 0
	end

	local physbone = ent:GetPhysicsObjectNum(boneid)
	if physbone:IsMotionEnabled() then
		physbone:EnableMotion(false)
		physbone:Wake()
		net.Start("rgmNotification")
			net.WriteUInt(BONE_FROZEN, 5)
		net.Send(pl)
	else
		physbone:EnableMotion(true)
		physbone:Wake()
		net.Start("rgmNotification")
			net.WriteUInt(BONE_UNFROZEN, 5)
		net.Send(pl)
	end
end)

local function RecursiveFindIfParent(ent, lockbone, locktobone)
	local parent = ent:GetBoneParent(locktobone)
	if parent then
		if parent == lockbone then
			return true
		elseif parent == -1 then
			return false
		else
			return RecursiveFindIfParent(ent, lockbone, parent)
		end
	end
end

local function RecursiveFindIfParentPropRagdoll(parentent, childent)
	local parent = childent.rgmPRparent
	if not parent then return false end

	parent = childent.rgmPRidtoent[parent]
	if parent == parentent then
		return true
	else
		return RecursiveFindIfParentPropRagdoll(parentent, parent)
	end
end

net.Receive("rgmLockToBone", function(len, pl)
	local lockent = net.ReadEntity()
	local lockedbone = net.ReadUInt(10)
	local originent = net.ReadEntity()
	local lockorigin = net.ReadUInt(10)

	if not rgmCanTool(lockent, pl) or not rgmCanTool(originent, pl) then return end
	if not IsValid(lockent) or not IsValid(originent) or not ((lockent:GetClass() == "prop_ragdoll") or (lockent:GetClass() == "prop_physics")) or not ((originent:GetClass() == "prop_ragdoll") or (originent:GetClass() == "prop_physics")) then return end
	if lockent.rgmPRenttoid then
		lockedbone = lockent.rgmPRenttoid[lockent]
	end
	if originent.rgmPRenttoid then
		lockorigin = originent.rgmPRenttoid[originent]
	end


	local physcheck = not lockent.rgmPRenttoid and (not rgm.BoneToPhysBone(lockent, lockedbone) or not rgm.BoneToPhysBone(originent, lockorigin))
	local samecheck = lockedbone == lockorigin

	if physcheck or samecheck then
		local err = samecheck and BONELOCK_FAILED_SAME or BONELOCK_FAILED_NOTPHYS

		net.Start("rgmNotification")
			net.WriteUInt(err, 5)
		net.Send(pl)
		return
	end

	if lockent == originent then
		if not RecursiveFindIfParent(lockent, lockedbone, lockorigin) then
			local bone = rgm.BoneToPhysBone(lockent, lockedbone)
			lockorigin = rgm.BoneToPhysBone(lockent, lockorigin)

			pl.rgmBoneLocks[lockent][bone] = { id = lockorigin, ent = lockent }
			pl.rgmPosLocks[lockent][bone] = nil
			pl.rgmAngLocks[lockent][bone] = nil

			net.Start("rgmLockToBoneResponse")
				net.WriteEntity(lockent)
				net.WriteUInt(lockedbone, 10)
			net.Send(pl)
		else
			net.Start("rgmNotification")
				net.WriteUInt(BONELOCK_FAILED, 5)
			net.Send(pl)
		end
	else
		if not RecursiveFindIfParentPropRagdoll(lockent, originent) then
			pl.rgmBoneLocks[lockent][lockedbone] = { id = lockorigin, ent = originent }
			pl.rgmPosLocks[lockent][lockedbone] = nil
			pl.rgmAngLocks[lockent][lockedbone] = nil

			net.Start("rgmLockToBoneResponse")
				net.WriteEntity(lockent)
				net.WriteUInt(0, 10)
			net.Send(pl)
		else
			net.Start("rgmNotification")
				net.WriteUInt(BONELOCK_FAILED, 5)
			net.Send(pl)
		end
	end
end)

net.Receive("rgmUnlockToBone", function(len, pl)
	local ent = net.ReadEntity()
	local unlockbone = net.ReadUInt(10)
	local bone = rgm.BoneToPhysBone(ent, unlockbone)

	if not rgmCanTool(ent, pl) then return end

	if ent.rgmPRenttoid then
		bone = ent.rgmPRenttoid[ent]
	end

	pl.rgmBoneLocks[ent][bone] = nil

	net.Start("rgmUnlockToBoneResponse")
		net.WriteEntity(ent)
		net.WriteUInt(unlockbone, 10)
	net.Send(pl)
end)

net.Receive("rgmLockConstrained", function(len, pl)
	local ent = net.ReadEntity()
	local lockent = net.ReadEntity()
	local physbone = 0

	if not rgmCanTool(ent, pl) then return end

	local convar = ConstrainedAllowed:GetBool()
	if not convar then
		net.Start("rgmNotification")
			net.WriteUInt(ENTLOCK_FAILED_NOTALLOWED, 5)
		net.Send(pl)
		return
	end

	if not IsValid(ent) or not IsValid(lockent) then return end

	if net.ReadBool() then
		local boneid = net.ReadUInt(8)

		if not ent.rgmPRenttoid then
			if not rgm.BoneToPhysBone(ent, boneid) then
				net.Start("rgmNotification")
					net.WriteUInt(ENTLOCK_FAILED_NONPHYS, 5)
				net.Send(pl)
				return
			end

			physbone = rgm.BoneToPhysBone(ent, boneid)
		else
			physbone = ent.rgmPRenttoid[ent]
		end
	end

	pl.rgmEntLocks[lockent] = {id = physbone, ent = ent}

	net.Start("rgmLockConstrainedResponse")
		net.WriteBool(true)
		net.WriteEntity(lockent)
	net.Send(pl)
end)

net.Receive("rgmUnlockConstrained", function(len, pl)
	local lockent = net.ReadEntity()

	if not IsValid(lockent) then return end
	if not rgmCanTool(lockent, pl) then return end

	pl.rgmEntLocks[lockent] = nil

	net.Start("rgmLockConstrainedResponse")
		net.WriteBool(false)
		net.WriteEntity(lockent)
	net.Send(pl)
end)

net.Receive("rgmSelectEntity", function(len, pl)
	local ent = net.ReadEntity()
	local resetlists = net.ReadBool()
	local tool = pl:GetTool("ragdollmover")
	if not tool then return end

	if not rgmCanTool(ent, pl) then return end

	if tool:GetClientNumber("lockselected") ~= 0 then
		net.Start("rgmNotification")
			net.WriteUInt(ENTSELECT_LOCKRESPONSE, 5)
		net.Send(pl)
		return
	end

	if not IsValid(ent) then return end

	pl.rgm.Entity = ent
	pl.rgm.Axis.EntAdvMerged = false
	pl.rgm.BoneToResetTo = (ent:GetClass() == "prop_ragdoll") and ent:TranslatePhysBoneToBone(0) or 0
	pl.rgmPosLocks = {}
	pl.rgmAngLocks = {}
	pl.rgmScaleLocks = {}
	pl.rgmBoneLocks = {}

	if ent.rgmPRidtoent then
		for id, e in pairs(ent.rgmPRidtoent) do
			pl.rgmPosLocks[e] = {}
			pl.rgmAngLocks[e] = {}
			pl.rgmScaleLocks[e] = {}
			pl.rgmBoneLocks[e] = {}
		end
	else
		pl.rgmPosLocks[ent] = {}
		pl.rgmAngLocks[ent] = {}
		pl.rgmScaleLocks[ent] = {}
		pl.rgmBoneLocks[ent] = {}
	end

	pl.rgmEntLocks = {}

	if not ent.rgmbonecached then -- also taken from locrotscale. some hacky way to cache the bones?
		local p = pl.rgmSwep:GetParent()
		pl.rgmSwep:FollowBone(ent, 0)
		pl.rgmSwep:SetParent(p)
		ent.rgmbonecached = true
	end

	rgmGetBone(pl, ent, 0)
	pl:rgmSync()

	local physchildren = rgmGetConstrainedEntities(ent)

	if not resetlists then
		net.Start("rgmUpdateEntInfo")
			net.WriteEntity(ent)

			net.WriteUInt(#physchildren, 13)
			for _, ent in ipairs(physchildren) do
				net.WriteEntity(ent)
			end
		net.Send(pl)
	else
		local children = rgmFindEntityChildren(ent)
		pl.rgm.PropRagdoll = ent.rgmPRidtoent and true or false

		net.Start("rgmUpdateLists")
			net.WriteBool(pl.rgm.PropRagdoll)
			if pl.rgm.PropRagdoll then
				local rgment = pl.rgm.Entity
				local count = #rgment.rgmPRidtoent + 1

				net.WriteUInt(count, 13) -- technically entity limit is 4096, but doubtful single prop ragdoll would reach that, but still...

				for id, entp in pairs(rgment.rgmPRidtoent) do
					net.WriteEntity(entp)
					net.WriteUInt(id, 13)

					net.WriteBool(entp.rgmPRparent and true or false)
					if entp.rgmPRparent then
						net.WriteUInt(entp.rgmPRparent, 13)
					end

					if entp == ent then
						net.WriteUInt(0, 13)
						continue
					end

					local entchildren = rgmFindEntityChildren(entp)
					net.WriteUInt(#entchildren, 13)

					for k, v in ipairs(entchildren) do
						net.WriteEntity(v)
					end
				end
			end

			net.WriteEntity(ent)

			net.WriteUInt(#children, 13)
			for k, v in ipairs(children) do
				net.WriteEntity(v)
			end

			net.WriteUInt(#physchildren, 13)
			for _, ent in ipairs(physchildren) do
				net.WriteEntity(ent)
			end
		net.Send(pl)
	end
end)

net.Receive("rgmSendBonePos", function(len, pl)
	local pos, ang, ppos, pang = net.ReadVector(), net.ReadAngle(), net.ReadVector(), net.ReadAngle()
	local childbones = {}

	for i = 1, net.ReadUInt(10) do
		local id, parent, pos, ang = net.ReadUInt(10), net.ReadUInt(10), net.ReadVector(), net.ReadAngle()
		if not childbones[parent] then
			childbones[parent] = {}
		end
		childbones[parent][id] = {}
		childbones[parent][id].pos = pos
		childbones[parent][id].ang = ang
	end

	if not pl.rgm then return end
	local entog = pl.rgm.Entity
	local ent = entog
	local axis = pl.rgm.Axis

	local boneog = pl.rgm.Bone
	local bone = boneog

	axis.EntAdvMerged = false

	local advbones = nil
	if ent:GetClass() == "ent_advbonemerge" then
		advbones = ent.AdvBone_BoneInfo
		if advbones and advbones[boneog] and advbones[boneog].parent and advbones[boneog].parent ~= "" then
			axis.EntAdvMerged = true
			ent = ent:GetParent()
			if ent.AttachedEntity then ent = ent.AttachedEntity end
		end
	end

	local physbones = {}

	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		physbones[ent:TranslatePhysBoneToBone(i)] = i
	end

	local function FindPhysParentRecursive(ent, bone, physbones)
		if physbones[bone] then 
			return physbones[bone]
		elseif bone == -1 then
			return -1
		else
			local parent = ent:GetBoneParent(bone)
			return FindPhysParentRecursive(ent, parent, physbones)
		end
	end

	if axis.EntAdvMerged then
		bone = ent:LookupBone(advbones[boneog].parent)
	end
	local parent = FindPhysParentRecursive(ent, bone, physbones)
	local physobj
	if parent ~= -1 then physobj = ent:GetPhysicsObjectNum(parent) end
	pl.rgm.GizmoParentID = parent

	local newpos, newang, nonpos
	nonpos = LocalToWorld(entog:GetManipulateBonePosition(boneog), angle_zero, ppos, pang)
	if parent ~= -1 then
		newpos, newang = WorldToLocal(pos, ang, physobj:GetPos(), physobj:GetAngles())
		pl.rgm.GizmoPParent, pl.rgm.GizmoParent = WorldToLocal(ppos, pang, physobj:GetPos(), physobj:GetAngles())
		nonpos = WorldToLocal(nonpos, pang, physobj:GetPos(), physobj:GetAngles())
	else
		newpos, newang = WorldToLocal(pos, ang, ent:GetPos(), ent:GetAngles())
		pl.rgm.GizmoPParent, pl.rgm.GizmoParent = WorldToLocal(ppos, pang, ent:GetPos(), ent:GetAngles())
		nonpos = WorldToLocal(nonpos, pang, ent:GetPos(), ent:GetAngles())
	end

	axis.GizmoAng = newang
	axis.GizmoPos = newpos

	pl.rgm.GizmoPos = newpos - nonpos
	if not (axis.EntAdvMerged) and ent:GetClass() then
		local manang = entog:GetManipulateBoneAngles(boneog)
		manang:Normalize()

		_, pl.rgm.GizmoAng = LocalToWorld(vector_origin, Angle(0, 0, -manang[3]), vector_origin, newang)
		_, pl.rgm.GizmoAng = LocalToWorld(vector_origin, Angle(-manang[1], 0, 0), vector_origin, pl.rgm.GizmoAng)
		_, pl.rgm.GizmoAng = LocalToWorld(vector_origin, Angle(0, -manang[2], 0), vector_origin, pl.rgm.GizmoAng)
	else
		pl.rgm.GizmoAng = axis.GizmoAng
	end

	local function CalcSkeleton(parent, physbones, childbones, ent, ppos, pang)
		if not childbones[parent] then return end
		for bone, tab in pairs(childbones[parent]) do
			local wpos, wang = tab.pos, tab.ang
			tab.pos, tab.ang = WorldToLocal(tab.pos, tab.ang, ppos, pang)
			CalcSkeleton(bone, physbones, childbones, ent, wpos, wang)
		end
	end

	CalcSkeleton(boneog, physbones, childbones, ent, pos, ang)

	pl.rgmBoneChildren = {}
	if next(childbones) then
		pl.rgmBoneChildren = childbones
	end

end)

net.Receive("rgmResetGizmo", function(len, pl)
	if not pl.rgm then return end
	pl.rgm.GizmoOffset:Set(vector_origin)

	net.Start("rgmUpdateGizmo")
		net.WriteVector(pl.rgm.GizmoOffset)
	net.Send(pl)
end)

net.Receive("rgmOperationSwitch", function(len, pl)
	local tool = pl:GetTool("ragdollmover")
	if not tool then return end

	tool:SetOperation(1)
end)

net.Receive("rgmSetGizmoToBone", function(len, pl)
	local vector = net.ReadVector()
	if not vector or not pl.rgm then return end
	local axis = pl.rgm.Axis
	local ent = pl.rgm.Entity

	if ent:GetClass() == "prop_ragdoll" and pl.rgm.IsPhysBone then
		ent = ent:GetPhysicsObjectNum(pl.rgm.PhysBone)
	end

	if axis.localoffset then
		vector = WorldToLocal(vector, angle_zero, ent:GetPos(), ent:GetAngles())
	else
		vector = WorldToLocal(vector, angle_zero, ent:GetPos(), angle_zero)
	end

	pl.rgm.GizmoOffset = vector

	net.Start("rgmUpdateGizmo")
		net.WriteVector(pl.rgm.GizmoOffset)
	net.Send(pl)
end)

local function RecursiveBoneFunc(bone, ent, func)
	func(bone)

	for _, id in ipairs(ent:GetChildBones(bone)) do
		RecursiveBoneFunc(id, ent, func)
	end
end

net.Receive("rgmResetAllBones", function(len, pl)
	local ent = net.ReadEntity()

	if not rgmCanTool(ent, pl) then return end

	for i = 0, ent:GetBoneCount() - 1 do
		local pos, ang, scale = ent:GetManipulateBonePosition(i), ent:GetManipulateBoneAngles(i), ent:GetManipulateBoneScale(i) -- Grabbing existing vectors as to not create new ones, in case ManipulateBone functions were overriden by something like Advanced Bonemerge
		pos:Set(vector_origin)
		ang:Set(angle_zero)
		scale:Set(VECTOR_SCALEDEF)

		ent:ManipulateBonePosition(i, pos)
		ent:ManipulateBoneAngles(i, ang)
		ent:ManipulateBoneScale(i, scale)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function() -- ask client to get new bone position info in case if the parent bone was moved. put into timer as it takes a bit of time for position to update on client?
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)

net.Receive("rgmResetAll", function(len, pl)
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(10)
	local children = net.ReadBool()

	if not IsValid(ent) then return end
	if not rgmCanTool(ent, pl) then return end

	if children then
		RecursiveBoneFunc(bone, ent, function(bon)
			local pos, ang, scale = ent:GetManipulateBonePosition(bon), ent:GetManipulateBoneAngles(bon), ent:GetManipulateBoneScale(bon)
			pos:Set(vector_origin)
			ang:Set(angle_zero)
			scale:Set(VECTOR_SCALEDEF)

			ent:ManipulateBonePosition(bon, pos)
			ent:ManipulateBoneAngles(bon, ang)
			ent:ManipulateBoneScale(bon, scale)
		end)
	else
		local pos, ang, scale = ent:GetManipulateBonePosition(bone), ent:GetManipulateBoneAngles(bone), ent:GetManipulateBoneScale(bone)
		pos:Set(vector_origin)
		ang:Set(angle_zero)
		scale:Set(VECTOR_SCALEDEF)

		ent:ManipulateBonePosition(bone, pos)
		ent:ManipulateBoneAngles(bone, ang)
		ent:ManipulateBoneScale(bone, scale)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function() -- ask client to get new bone position info in case if the parent bone was moved. put into timer as it takes a bit of time for position to update on client?
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)

net.Receive("rgmResetPos", function(len, pl)
	local ent = net.ReadEntity()
	local children = net.ReadBool()
	local bone = net.ReadUInt(10)

	if not IsValid(ent) then return end
	if not rgmCanTool(ent, pl) then return end

	if children then
		RecursiveBoneFunc(bone, ent, function(bon) 
			local pos = ent:GetManipulateBonePosition(bon)
			pos:Set(vector_origin)

			ent:ManipulateBonePosition(bon, pos)
		end)
	else
		local pos = ent:GetManipulateBonePosition(bone)
		pos:Set(vector_origin)

		ent:ManipulateBonePosition(bone, pos)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function()
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)

net.Receive("rgmResetAng", function(len, pl)
	local ent = net.ReadEntity()
	local children = net.ReadBool()
	local bone = net.ReadUInt(10)

	if not rgmCanTool(ent, pl) then return end

	if children then
		RecursiveBoneFunc(bone, ent, function(bon) 
			local ang = ent:GetManipulateBoneAngles(bon)
			ang:Set(angle_zero)

			ent:ManipulateBoneAngles(bon, ang)
		end)
	else
		local ang = ent:GetManipulateBoneAngles(bone)
		ang:Set(angle_zero)

		ent:ManipulateBoneAngles(bone, ang)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function()
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)

net.Receive("rgmResetScale", function(len, pl)
	local ent = net.ReadEntity()
	local children = net.ReadBool()
	local bone = net.ReadUInt(10)

	if not rgmCanTool(ent, pl) then return end

	if children then
		RecursiveBoneFunc(bone, ent, function(bon)
			local scale = ent:GetManipulateBoneScale(bon)
			scale:Set(VECTOR_SCALEDEF)

			ent:ManipulateBoneScale(bon, scale)
		end)
	else
		local scale = ent:GetManipulateBoneScale(bone)
		scale:Set(VECTOR_SCALEDEF)

		ent:ManipulateBoneScale(bone, scale)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function()
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)

local VECTOR_NEARZERO = Vector(0.01, 0.01, 0.01)

net.Receive("rgmScaleZero", function(len, pl)
	local ent = net.ReadEntity()
	local children = net.ReadBool()
	local bone = net.ReadUInt(10)

	if not rgmCanTool(ent, pl) then return end

	if children then
		RecursiveBoneFunc(bone, ent, function(bon)
			local scale = ent:GetManipulateBoneScale(bon)
			scale:Set(VECTOR_NEARZERO)

			ent:ManipulateBoneScale(bon, scale)
		end)
	else
		local scale = ent:GetManipulateBoneScale(bone)
		scale:Set(VECTOR_NEARZERO)

		ent:ManipulateBoneScale(bone, scale)
	end

	net.Start("rgmUpdateSliders")
	net.Send(pl)

	timer.Simple(0.1, function()
		net.Start("rgmRequestBonePos")
		net.Send(pl)
	end)
end)



net.Receive("rgmPrepareOffsets", function(len, pl)
	if not pl.rgm then return end
	if pl.rgm.physmove ~= 1 then return end
	local tool = pl:GetTool("ragdollmover")
	if not tool then return end

	local ent, axis = pl.rgm.Entity, pl.rgm.Axis
	local bone = pl.rgm.Bone

	if not rgmCanTool(ent, pl) then return end

	pl.rgm.UIMoving = true

	pl.rgm.NPhysBonePos = ent:GetManipulateBonePosition(bone)
	pl.rgm.NPhysBoneAng = ent:GetManipulateBoneAngles(bone)
	pl.rgm.NPhysBoneScale = ent:GetManipulateBoneScale(bone)

	if pl.rgm.IsPhysBone then
		if axis.smovechildren then
			if _G["physundo"] and _G["physundo"].Create then
				_G["physundo"].Create(ent, pl)
			end
		end

		local obj = ent:GetPhysicsObjectNum(pl.rgm.PhysBone)
		if obj then
			pl.rgmOffsetTable = rgm.GetOffsetTable(tool, ent, pl.rgm.Rotate, pl.rgmBoneLocks, pl.rgmEntLocks)
		end
	elseif pl.rgm.NextPhysBone then
		if _G["physundo"] and _G["physundo"].Create then
			_G["physundo"].Create(ent, pl)
		end

		local obj = ent:GetPhysicsObjectNum(pl.rgm.NextPhysBone)
		if obj then
			pl.rgmOffsetTable = rgm.GetNPOffsetTable(tool, ent, pl.rgm.Rotate, {p = pl.rgm.NextPhysBone, pos = axis.GizmoPos, ang = axis.GizmoAng}, pl.rgmPhysMove, pl.rgmBoneLocks, pl.rgmEntLocks)
		end
	end
end)

net.Receive("rgmClearOffsets", function(len, pl)
	if not pl.rgm then return end
	if pl.rgm.physmove ~= 1 then return end
	local tool = pl:GetTool("ragdollmover")
	if not tool then return end
	local ent = pl.rgm.Entity

	if not rgmCanTool(ent, pl) then return end

	pl.rgm.UIMoving = false

	if pl.rgm.IsPhysBone or (pl.rgm.physmove ~= 0 and pl.rgm.NextPhysBone) then
		if (pl.rgm.unfreeze or 1) ~= 0 then
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				if pl.rgmOffsetTable[i].moving then
					local obj = ent:GetPhysicsObjectNum(i)
					obj:EnableMotion(true)
					obj:Wake()
				end
				if pl.rgmOffsetTable[i].locked and ConstrainedAllowed:GetBool() then
					for lockent, bonetable in pairs(pl.rgmOffsetTable[i].locked) do
						for j = 0, lockent:GetPhysicsObjectCount() - 1 do
							if  bonetable[j].moving then
								local obj = lockent:GetPhysicsObjectNum(j)
								obj:EnableMotion(true)
								obj:Wake()
							end
						end
					end
				end
			end
		end
	end

	rgmCalcGizmoPos(pl)
end)

net.Receive("rgmAdjustBone", function(len, pl)
	local manipulate_bone = {}
	local ent = pl.rgm.Entity
	local childbones = pl.rgmBoneChildren
	local physmove = pl.rgm.physmove ~= 0
	if not IsValid(ent) or not rgmCanTool(ent, pl) then net.ReadInt(3) net.ReadInt(3) net.ReadFloat() return end
	local rgmaxis = pl.rgm.Axis

	manipulate_bone[1] = function(axis, value)
		local change = ent:GetManipulateBonePosition(pl.rgm.Bone)
		change[axis] = value

		ent:ManipulateBonePosition(pl.rgm.Bone, change)

		if ent:GetClass() == "prop_ragdoll" and physmove and pl.rgm.NextPhysBone then -- moving physical if allowed
			local tool = pl:GetTool("ragdollmover")
			local ang = ent:GetManipulateBoneAngles(pl.rgm.Bone)

			local pbone = pl.rgm.NextPhysBone
			local obj = ent:GetPhysicsObjectNum(pbone)

			local opos, oang = obj:GetPos(), obj:GetAngles()
			local nbpos = LocalToWorld(rgmaxis.GizmoPos, rgmaxis.GizmoAng, opos, oang)
			local _, gizmoang = LocalToWorld(vector_origin, pl.rgm.GizmoAng, vector_origin, oang)

			local npos, nang = LocalToWorld(vector_origin, ang, vector_origin, gizmoang)
			npos = LocalToWorld(change - pl.rgm.NPhysBonePos, angle_zero, nbpos, rgmaxis.GizmoParent)

			local postable = rgm.SetOffsets(tool, ent, pl.rgmOffsetTable, {b = pbone, p = obj:GetPos(), a = obj:GetAngles()}, pl.rgmAngLocks, pl.rgmPosLocks, {pos = npos, ang = nang})

			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				if postable[i] and not postable[i].dontset then
					local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
					local boneid = not pl.rgm.PropRagdoll and i or 0
					local obj = ent:GetPhysicsObjectNum(boneid)

					obj:EnableMotion(true)
					obj:Wake()
					obj:SetPos(postable[i].pos)
					obj:SetAngles(postable[i].ang)
					obj:EnableMotion(false)
					obj:Wake()
				end

				if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
					for lockent, bones in pairs(postable[i].locked) do
						for j = 0, lockent:GetPhysicsObjectCount() - 1 do
							if bones[j] then
								local obj = lockent:GetPhysicsObjectNum(j)

								obj:EnableMotion(true)
								obj:Wake()
								obj:SetPos(bones[j].pos)
								obj:SetAngles(bones[j].ang)
								obj:EnableMotion(false)
								obj:Wake()
							end
						end
					end
				end
			end
		end
	end

	manipulate_bone[2] = function(axis, value)
		local change = ent:GetManipulateBoneAngles(pl.rgm.Bone)
		change[axis] = value

		ent:ManipulateBoneAngles(pl.rgm.Bone, change)

		if ent:GetClass() == "prop_ragdoll" and physmove and pl.rgm.NextPhysBone then -- moving physical if allowed
			local tool = pl:GetTool("ragdollmover")
			local pos = ent:GetManipulateBonePosition(pl.rgm.Bone)

			local pbone = pl.rgm.NextPhysBone
			local obj = ent:GetPhysicsObjectNum(pbone)

			local opos, oang = obj:GetPos(), obj:GetAngles()
			local nbpos = LocalToWorld(rgmaxis.GizmoPos, rgmaxis.GizmoAng, opos, oang)
			local _, gizmoang = LocalToWorld(vector_origin, pl.rgm.GizmoAng, vector_origin, oang)

			local npos, nang = LocalToWorld(vector_origin, change, vector_origin, gizmoang)
			npos = LocalToWorld(pos - pl.rgm.NPhysBonePos, angle_zero, nbpos, rgmaxis.GizmoParent)

			local postable = rgm.SetOffsets(tool, ent, pl.rgmOffsetTable, {b = pbone, p = obj:GetPos(), a = obj:GetAngles()}, pl.rgmAngLocks, pl.rgmPosLocks, {pos = npos, ang = nang})

			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				if postable[i] and not postable[i].dontset then
					local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
					local boneid = not pl.rgm.PropRagdoll and i or 0
					local obj = ent:GetPhysicsObjectNum(boneid)

					obj:EnableMotion(true)
					obj:Wake()
					obj:SetPos(postable[i].pos)
					obj:SetAngles(postable[i].ang)
					obj:EnableMotion(false)
					obj:Wake()
				end

				if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
					for lockent, bones in pairs(postable[i].locked) do
						for j = 0, lockent:GetPhysicsObjectCount() - 1 do
							if bones[j] then
								local obj = lockent:GetPhysicsObjectNum(j)

								obj:EnableMotion(true)
								obj:Wake()
								obj:SetPos(bones[j].pos)
								obj:SetAngles(bones[j].ang)
								obj:EnableMotion(false)
								obj:Wake()
							end
						end
					end
				end
			end
		end
	end

	manipulate_bone[3] = function(axis, value)
		local bone = pl.rgm.Bone
		local prevscale = ent:GetManipulateBoneScale(bone)
		local change = ent:GetManipulateBoneScale(bone)
		change[axis] = value

		if rgmaxis.scalechildren and not (ent:GetClass() == "ent_advbonemerge") then
			local scalediff = change - prevscale
			local diff
			local noscale = pl.rgmScaleLocks
			local RecursiveBoneScale

			if rgmaxis.smovechildren and childbones and childbones[bone] then
				diff = Vector(change.x / prevscale.x, change.y / prevscale.y, change.z / prevscale.z)

				RecursiveBoneScale = function(ent, bone, scale, diff, ppos, pang)
					if noscale[ent][bone] and not (pl.rgm.Bone == bone) then 
						scale = vector_origin
						diff = VECTOR_SCALEDEF
					end

					local oldscale = ent:GetManipulateBoneScale(bone)
					ent:ManipulateBoneScale(bone, oldscale + scale)

					if childbones[bone] then
						for cbone, tab in pairs(childbones[bone]) do
							local pos = tab.pos
							local bonepos = ent:GetManipulateBonePosition(cbone)
							local newpos = Vector(pos.x * diff.x, pos.y * diff.y, pos.z * diff.z)
							local wpos, wang = nil, nil
							ent:ManipulateBonePosition(cbone, bonepos + (newpos - pos))
							if ent:GetClass() == "prop_ragdoll" then
								wpos, wang = LocalToWorld(newpos, tab.ang, ppos, pang)
								tab.wpos = wpos
							end
							tab.pos = newpos

							RecursiveBoneScale(ent, cbone, scale, diff, wpos, wang)
						end
					end
				end
			else
				RecursiveBoneScale = function(ent, bone, scale)
					if noscale[ent][bone] then return end

					local oldscale = ent:GetManipulateBoneScale(bone)
					ent:ManipulateBoneScale(bone, oldscale + scale)

					for _, cbone in ipairs(ent:GetChildBones(bone)) do
						RecursiveBoneScale(ent, cbone, scale)
					end
				end
			end

			if ent:GetClass() == "prop_ragdoll" then
				local obj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
				if IsValid(obj) then
					local ppos, pang = obj:GetPos(), obj:GetAngles()
					ppos, pang = LocalToWorld(rgmaxis.GizmoPos, rgmaxis.GizmoAng, ppos, pang)
					RecursiveBoneScale(ent, bone, scalediff, diff, ppos, pang)
				end
			else
				RecursiveBoneScale(ent, bone, scalediff, diff)
			end
		else
			if rgmaxis.smovechildren and childbones and childbones[bone] and not (ent:GetClass() == "ent_advbonemerge") then
				local diff = Vector(change.x / prevscale.x, change.y / prevscale.y, change.z / prevscale.z)
				local obj
				local ppos, pang

				if ent:GetClass() == "prop_ragdoll" then
					obj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
					if IsValid(obj) then
						ppos, pang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, obj:GetPos(), obj:GetAngles())
					end
				end

				for cbone, tab in pairs(childbones[bone]) do
					local pos = tab.pos
					local bonepos = ent:GetManipulateBonePosition(cbone)
					local newpos = Vector(pos.x * diff.x, pos.y * diff.y, pos.z * diff.z)
					local wpos, wang
					ent:ManipulateBonePosition(cbone, bonepos + (newpos - pos))
					if ent:GetClass() == "prop_ragdoll" then
						wpos, wang = LocalToWorld(newpos, tab.ang, ppos, pang)
						tab.wpos = wpos
						rgmAdjustScaleTable(cbone, childbones, wpos, wang)
					end
					tab.pos = newpos
				end
			end

			ent:ManipulateBoneScale(bone, change)
		end

		if ent:GetClass() == "prop_ragdoll" and physmove and (IsValid(ent:GetPhysicsObjectNum(pl.rgm.PhysBone)) or IsValid(ent:GetPhysicsObjectNum(pl.rgm.NextPhysBone))) and rgmaxis.smovechildren then -- moving physical if allowed
			local pbone = pl.rgm.PhysBone
			local prevscale = pl.rgm.NPhysBoneScale
			if pl.rgm.NextPhysBone then
				pbone = pl.rgm.NextPhysBone
			end
			local obj = ent:GetPhysicsObjectNum(pbone)

			local p, a = obj:GetPos(), obj:GetAngles()
			local npos, nang = LocalToWorld(rgmaxis.GizmoPos, rgmaxis.GizmoAng, p, a)
			local diff = Vector(change.x / prevscale.x, change.y / prevscale.y, change.z / prevscale.z)
			local sbone = pl.rgm.IsPhysBone and {b = pbone, p = p, a = a} or {}
			local postable = rgm.SetScaleOffsets(self, ent, pl.rgmOffsetTable, sbone, diff, pl.rgmPosLocks, pl.rgmScaleLocks, rgmaxis.scalechildren, {b = pl.rgm.Bone, pos = npos, ang = nang}, childbones)

			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				if postable[i] and not postable[i].dontset then
					local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
					local boneid = not pl.rgm.PropRagdoll and i or 0
					local obj = ent:GetPhysicsObjectNum(boneid)

					obj:EnableMotion(true)
					obj:Wake()
					obj:SetPos(postable[i].pos)
					obj:SetAngles(postable[i].ang)
					obj:EnableMotion(false)
					obj:Wake()
				end

				if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
					for lockent, bones in pairs(postable[i].locked) do
						for j = 0, lockent:GetPhysicsObjectCount() - 1 do
							if bones[j] then
								local obj = lockent:GetPhysicsObjectNum(j)

								obj:EnableMotion(true)
								obj:Wake()
								obj:SetPos(bones[j].pos)
								obj:SetAngles(bones[j].ang)
								obj:EnableMotion(false)
								obj:Wake()
							end
						end
					end
				end
			end
		end
	end

	local mode, axis, value = net.ReadInt(3), net.ReadInt(3), net.ReadFloat()
	if mode == 3 and value == 0 then value = 0.01 end

	manipulate_bone[mode](axis, value)

	if not pl.rgm.UIMoving then
		rgmCalcGizmoPos(pl)
	end
end)

net.Receive("rgmGizmoOffset", function(len, pl)
	local axis = net.ReadUInt(2)
	local value = net.ReadFloat()

	pl.rgm.GizmoOffset[axis] = value
end)

net.Receive("rgmUpdateCCVar", function(len, pl)
	local var = net.ReadUInt(4)
	if not pl.rgm or not IsValid(pl.rgm.Axis) then return end
	local tool = pl:GetTool("ragdollmover")
	if not tool then return end

	local axis = pl.rgm.Axis
	local vars = {
		"localpos",
		"localang",
		"localoffset",
		"relativerotate",
		"scalechildren",
		"smovechildren",
		"updaterate",
		"unfreeze",
		"snapenable",
		"snapamount",
		"physmove"
	}

	if var < 7 and IsValid(axis) then
		axis[vars[var]] = (tool:GetClientNumber(vars[var], 1) ~= 0)
	else
		pl.rgm[vars[var]] = tool:GetClientNumber(vars[var], 1)
		if var == 10 then
			pl.rgm.snapamount = pl.rgm.snapamount < 1 and 1 or pl.rgm.snapamount
		end
	end
end)

hook.Add("PlayerDisconnected", "RGMCleanupGizmos", function(pl)
	if IsValid(pl.rgm.Axis) then
		pl.rgm.Axis:Remove()
	end
end)

hook.Add("EntityRemoved", "RGMDeselectEntity", function(ent)
	for id, pl in ipairs(player.GetAll()) do
		if pl.rgm and pl.rgm.Entity == ent  then
			pl.rgm.Entity = nil
			pl.rgm.Axis.EntAdvMerged = false
			net.Start("rgmDeselectEntity")
			net.Send(pl)
		end
	end
end)

end

concommand.Add("ragdollmover_resetroot", function(pl)
	if not pl.rgm or not IsValid(pl.rgm.Entity) then return end
	local bone = pl.rgm.Bone

	rgmGetBone(pl, pl.rgm.Entity, pl.rgm.BoneToResetTo)
	pl.rgm.BoneToResetTo = bone

	pl:rgmSync()

	net.Start("rgmSelectBoneResponse")
		net.WriteBool(pl.rgm.IsPhysBone)
		net.WriteEntity(pl.rgm.Entity)
		net.WriteUInt(pl.rgm.Bone, 10)
	net.Send(pl)
end)

function TOOL:Deploy()
	if SERVER then
		local pl = self:GetOwner()
		local axis = pl.rgm.Axis
		if not IsValid(axis) then
			axis = ents.Create("rgm_axis")
			axis:SetPos(pl:EyePos())
			axis:Spawn()
			axis.Owner = pl
			axis.localpos = self:GetClientNumber("localpos", 0) ~= 0
			axis.localang = self:GetClientNumber("localang", 1) ~= 0
			axis.localoffset = self:GetClientNumber("localoffset", 1) ~= 0
			axis.relativerotate = self:GetClientNumber("relativerotate", 0) ~= 0
			axis.scalechildren = self:GetClientNumber("scalechildren", 0) ~= 0
			axis.smovechildren = self:GetClientNumber("smovechildren", 0) ~= 0
			pl.rgm.Axis = axis

			pl.rgm.updaterate = self:GetClientNumber("updaterate", 0.01)
			pl.rgm.unfreeze = self:GetClientNumber("unfreeze", 0)
			pl.rgm.snapenable = self:GetClientNumber("snapenable", 0)
			pl.rgm.snapamount = self:GetClientNumber("snapamount", 30)
			pl.rgm.physmove = self:GetClientNumber("physmove", 0)
		end
	end
end

local function EntityFilter(ent, tool)
	return (ent:GetClass() == "prop_ragdoll" or ent:GetClass() == "prop_physics" or ent:GetClass() == "prop_effect") or (tool:GetClientNumber("disablefilter") ~= 0 and not ent:IsWorld())
end

function TOOL:LeftClick(tr)

	if self:GetOperation() == 1 then

		if SERVER then
			local pl = self:GetOwner()
			local axis, ent = pl.rgm.Axis, pl.rgm.Entity

			if not IsValid(axis) or not IsValid(ent) then self:SetOperation(0) return true end
			local offset = tr.HitPos
			local ogpos, ogang

			if not pl.rgm.IsPhysBone then
				if axis.EntAdvMerged then
					ent = ent:GetParent()
					if ent.AttachedEntity then ent = ent.AttachedEntity end
				end
				if pl.rgm.GizmoParentID ~= -1 then
					local physobj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
					ogpos, ogang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, physobj:GetPos(), physobj:GetAngles())
				else
					ogpos, ogang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, ent:GetPos(), ent:GetAngles())
				end
			elseif ent:GetClass() == "prop_ragdoll" then
				ent = ent:GetPhysicsObjectNum(pl.rgm.PhysBone)
				ogpos, ogang = ent:GetPos(), ent:GetAngles()
			elseif ent:GetClass() == "prop_physics" then
				ent = ent:GetPhysicsObjectNum(0)
				ogpos, ogang = ent:GetPos(), ent:GetAngles()
			end

			if axis.localoffset then
				offset = WorldToLocal(offset, angle_zero, ogpos, ogang)
			else
				offset = WorldToLocal(offset, angle_zero, ogpos, angle_zero)
			end

			pl.rgm.GizmoOffset = offset

			net.Start("rgmUpdateGizmo")
				net.WriteVector(pl.rgm.GizmoOffset)
			net.Send(pl)
		end

		self:SetOperation(0)
		return true

	end

	if CLIENT then return false end

	local pl = self:GetOwner()

	if pl.rgm.Moving then return false end

	local axis = pl.rgm.Axis
	if not IsValid(axis) then
		axis = ents.Create("rgm_axis")
		axis:SetPos(pl:EyePos())
		axis:Spawn()
		axis.Owner = pl
		pl.rgm.Axis = axis
		return false
	end

	local ent = pl.rgm.Entity
	local collision = axis:TestCollision(pl, self:GetClientNumber("scale", 10))

	if collision and IsValid(ent) and rgmCanTool(ent, pl) then

		if _G["physundo"] and _G["physundo"].Create then
			_G["physundo"].Create(ent, pl)
		end

		local apart = collision.axis

		pl.rgmISPos = collision.hitpos*1
		pl.rgmISDir = apart:GetAngles():Forward()

		pl.rgmOffsetPos = WorldToLocal(apart:GetPos(), apart:GetAngles(), collision.hitpos, apart:GetAngles())

		local opos = apart:WorldToLocal(collision.hitpos)
		local grabang = apart:LocalToWorldAngles(Angle(0, 0, Vector(opos.y, opos.z, 0):Angle().y))
		if pl.rgm.IsPhysBone then
			local obj = ent:GetPhysicsObjectNum(pl.rgm.PhysBone)
			if obj then 
				_, pl.rgmOffsetAng = WorldToLocal(vector_origin, obj:GetAngles(), vector_origin, grabang)
				pl.rgmOffsetTable = rgm.GetOffsetTable(self, ent, pl.rgm.Rotate, pl.rgmBoneLocks, pl.rgmEntLocks)
			end
		elseif pl.rgm.NextPhysBone and pl.rgm.physmove ~= 0 then
			local obj = ent:GetPhysicsObjectNum(pl.rgm.NextPhysBone)
			if obj then 
				_, pl.rgmOffsetAng = WorldToLocal(vector_origin, obj:GetAngles(), vector_origin, grabang)
				pl.rgmOffsetTable = rgm.GetNPOffsetTable(self, ent, pl.rgm.Rotate, {p = pl.rgm.NextPhysBone, pos = axis.GizmoPos, ang = axis.GizmoAng}, pl.rgmPhysMove, pl.rgmBoneLocks, pl.rgmEntLocks)
			end
		end
		if IsValid(ent:GetParent()) and not (ent:GetClass() == "prop_ragdoll") then -- ragdolls don't seem to care about parenting
			local pang = ent:GetParent():LocalToWorldAngles(ent:GetLocalAngles())
			_, pl.rgmOffsetAng = WorldToLocal(apart:GetPos(), pang, apart:GetPos(), grabang)
		end

		pl.rgm.StartAngle = WorldToLocal(collision.hitpos, angle_zero, apart:GetPos(), apart:GetAngles())

		pl.rgm.NPhysBonePos = ent:GetManipulateBonePosition(pl.rgm.Bone)
		pl.rgm.NPhysBoneAng = ent:GetManipulateBoneAngles(pl.rgm.Bone)
		pl.rgm.NPhysBoneScale = ent:GetManipulateBoneScale(pl.rgm.Bone)

		local ignore = { pl }

		if ent.rgmPRidtoent then
			for id, e in pairs(ent.rgmPRidtoent) do
				ignore[#ignore + 1] = e
			end
		else
			ignore[2] = ent
		end

		local function FindRecursiveIfParent(findid, id, ent)
			if ent.rgmPRidtoent then
				if ent.rgmPRparent then
					if ent.rgmPRparent == findid then return true end
					return FindRecursiveIfParent(findid, ent.rgmPRparent, ent.rgmPRidtoent[ent.rgmPRparent])
				else
					return false
				end
			else
				local parent = rgm.GetPhysBoneParent(ent, id)
				if parent then
					if parent == findid then return true end
					return FindRecursiveIfParent(findid, parent, ent)
				else
					return false
				end
			end
		end

		if pl.rgm.IsPhysBone or (pl.rgm.NextPhysBone and pl.rgm.physmove ~= 0) then
			for lockent, data in pairs(pl.rgmEntLocks) do
				if FindRecursiveIfParent(data.id, pl.rgm.PhysBone, ent) then continue end
				ignore[#ignore + 1] = lockent
			end
		end

		pl.rgm.Ignore = ignore

		local dirnorm = (collision.hitpos - axis:GetPos())
		dirnorm:Normalize()
		pl.rgm.DirNorm = dirnorm
		pl.rgm.MoveAxis = apart.id
		pl.rgm.Moving = true
		pl:rgmSync()
		return false

	elseif IsValid(tr.Entity) and EntityFilter(tr.Entity, self) and rgmCanTool(tr.Entity, pl) then

		local entity = tr.Entity

		if entity ~= pl.rgm.Entity and self:GetClientNumber("lockselected") ~= 0 then
			net.Start("rgmNotification")
				net.WriteUInt(ENTSELECT_LOCKRESPONSE, 5)
			net.Send(pl)
			return false
		end

		pl.rgm.Entity = entity
		axis.EntAdvMerged = false

		if not entity.rgmbonecached then -- also taken from locrotscale. some hacky way to cache the bones?
			pl.rgmSwep = self.SWEP
			local p = pl.rgmSwep:GetParent()
			pl.rgmSwep:FollowBone(entity, 0)
			pl.rgmSwep:SetParent(p)
			entity.rgmbonecached = true
		end

		rgmGetBone(pl, entity, entity:TranslatePhysBoneToBone(tr.PhysicsBone))
		pl.rgm.BoneToResetTo = (entity:GetClass() == "prop_ragdoll") and entity:TranslatePhysBoneToBone(0) or 0 -- used for quickswitching to root bone and back

		if ent ~= entity and (not entity.rgmPRenttoid or not entity.rgmPRenttoid[ent]) then
			local children = rgmFindEntityChildren(entity)
			local physchildren = rgmGetConstrainedEntities(entity)
			pl.rgm.PropRagdoll = entity.rgmPRidtoent and true or false

			net.Start("rgmUpdateLists")
				net.WriteBool(pl.rgm.PropRagdoll)
				if pl.rgm.PropRagdoll then
					local rgment = pl.rgm.Entity
					local count = #rgment.rgmPRidtoent + 1

					net.WriteUInt(count, 13) -- technically entity limit is 4096, but doubtful single prop ragdoll would reach that, but still...

					for id, ent in pairs(rgment.rgmPRidtoent) do
						net.WriteEntity(ent)
						net.WriteUInt(id, 13)

						net.WriteBool(ent.rgmPRparent and true or false)
						if ent.rgmPRparent then
							net.WriteUInt(ent.rgmPRparent, 13)
						end

						if ent == entity then
							net.WriteUInt(0, 13)
							continue
						end

						local entchildren = rgmFindEntityChildren(ent)
						net.WriteUInt(#entchildren, 13)

						for k, v in ipairs(entchildren) do
							net.WriteEntity(v)
						end
					end
				end

				net.WriteEntity(entity)

				net.WriteUInt(#children, 13)
				for k, v in ipairs(children) do
					net.WriteEntity(v)
				end

				net.WriteUInt(#physchildren, 13)
				for _, ent in ipairs(physchildren) do
					net.WriteEntity(ent)
				end
			net.Send(pl)

			pl.rgmPosLocks = {}
			pl.rgmAngLocks = {}
			pl.rgmScaleLocks = {}
			pl.rgmBoneLocks = {}

			if entity.rgmPRidtoent then
				for id, ent in pairs(entity.rgmPRidtoent) do
					pl.rgmPosLocks[ent] = {}
					pl.rgmAngLocks[ent] = {}
					pl.rgmScaleLocks[ent] = {}
					pl.rgmBoneLocks[ent] = {}
				end
			else
				pl.rgmPosLocks[entity] = {}
				pl.rgmAngLocks[entity] = {}
				pl.rgmScaleLocks[entity] = {}
				pl.rgmBoneLocks[entity] = {}
			end

			pl.rgmEntLocks = {}
		end

		pl:rgmSync()

		net.Start("rgmSelectBoneResponse")
			net.WriteBool(pl.rgm.IsPhysBone)
			net.WriteEntity(pl.rgm.Entity)
			net.WriteUInt(pl.rgm.Bone, 10)
		net.Send(pl)
	end

	return false
end

function TOOL:RightClick(tr)

	if self:GetOperation() == 1 then

		if SERVER then
			local pl = self:GetOwner()
			local axis = pl.rgm.Axis
			local ent, rgment = tr.Entity, pl.rgm.Entity
			local offset

			if not IsValid(axis) or not IsValid(rgment) then self:SetOperation(0) return true end

			if IsValid(ent) then
				local object = ent:GetPhysicsObjectNum(tr.PhysicsBone)
				if not object then object = ent end
				offset = object:GetPos()
			else
				offset = tr.HitPos
			end

			local ogpos, ogang

			if not pl.rgm.IsPhysBone then
				if axis.EntAdvMerged then
					rgment = rgment:GetParent()
					if rgment.AttachedEntity then rgment = rgment.AttachedEntity end
				end
				if pl.rgm.GizmoParentID ~= -1 then
					local physobj = rgment:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
					ogpos, ogang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, physobj:GetPos(), physobj:GetAngles())
				else
					ogpos, ogang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, rgment:GetPos(), rgment:GetAngles())
				end
			elseif rgment:GetClass() == "prop_ragdoll" then
				rgment = rgment:GetPhysicsObjectNum(pl.rgm.PhysBone)
				ogpos, ogang = rgment:GetPos(), rgment:GetAngles()
			elseif rgment:GetClass() == "prop_physics" then
				rgment = rgment:GetPhysicsObjectNum(0)
				ogpos, ogang = rgment:GetPos(), rgment:GetAngles()
			end

			if axis.localoffset then
				offset = WorldToLocal(offset, angle_zero, ogpos, ogang)
			else
				offset = WorldToLocal(offset, angle_zero, ogpos, angle_zero)
			end

			pl.rgm.GizmoOffset = offset

			net.Start("rgmUpdateGizmo")
				net.WriteVector(pl.rgm.GizmoOffset)
			net.Send(pl)
		end

		self:SetOperation(0)
		return true

	end

	return false
end

function TOOL:Reload()
	if CLIENT then return false end
	if self:GetOperation() == 1 then
		self:SetOperation(0)
		return false
	end

	RunConsoleCommand("ragdollmover_resetroot")
	return false
end

do

local pl

function TOOL:Think()

if SERVER then

	local pl = self:GetOwner()

	if not self.LastThink then self.LastThink = CurTime() end
	if CurTime() < self.LastThink + (pl.rgm.updaterate or 0.01) then return end

	local ent = pl.rgm.Entity
	local axis = pl.rgm.Axis

	local moving = pl.rgm.Moving or false
	local rotate = pl.rgm.Rotate or false
	local scale = pl.rgm.Scale or false
	local physmove = pl.rgm.physmove ~= 0

	if moving then
		if not pl:KeyDown(IN_ATTACK) or not rgmCanTool(ent, pl) then

			if pl.rgm.IsPhysBone or (physmove and pl.rgm.NextPhysBone) then
				if (pl.rgm.unfreeze or 1) ~= 0 then
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						if pl.rgmOffsetTable[i].moving then
							local obj = ent:GetPhysicsObjectNum(i)
							obj:EnableMotion(true)
							obj:Wake()
						end
						if pl.rgmOffsetTable[i].locked and ConstrainedAllowed:GetBool() then
							for lockent, bonetable in pairs(pl.rgmOffsetTable[i].locked) do
								for j = 0, lockent:GetPhysicsObjectCount() - 1 do
									if  bonetable[j].moving then
										local obj = lockent:GetPhysicsObjectNum(j)
										obj:EnableMotion(true)
										obj:Wake()
									end
								end
							end
						end
					end
				end
			end

			rgmCalcGizmoPos(pl)

			pl.rgm.Moving = false
			pl:rgmSyncOne("Moving")
			net.Start("rgmUpdateSliders")
			net.Send(pl)
			return
		end

		if not IsValid(axis) then return end

		local eyepos, eyeang = rgm.EyePosAng(pl)

		local apart = axis[RGMGIZMOS.GizmoTable[pl.rgm.MoveAxis]]
		local bone = pl.rgm.PhysBone

		if not IsValid(ent) then
			pl.rgm.Moving = false
			return
		end

		local tracepos = nil
		if pl:KeyDown(IN_SPEED) then
			local tr = util.TraceLine({
				start = pl:EyePos(),
				endpos = pl:EyePos() + pl:GetAimVector() * 4096,
				filter = pl.rgm.Ignore
			})
			tracepos = tr.HitPos
		end

		local snapamount = 0
		if pl.rgm.snapenable ~= 0 then
			snapamount = pl.rgm.snapamount
		end

		local physbonecount = ent:GetBoneCount() - 1
		if physbonecount == nil then return end

		if not scale then
			if IsValid(ent:GetParent()) and bone == 0 and not ent:IsEffectActive(EF_BONEMERGE) and not ent:IsEffectActive(EF_FOLLOWBONE) and not (ent:GetClass() == "prop_ragdoll") then -- is parented
				local pos, ang = apart:ProcessMovement(pl.rgmOffsetPos, pl.rgmOffsetAng, eyepos, eyeang, ent, bone, pl.rgmISPos, pl.rgmISDir, 0, snapamount, pl.rgm.StartAngle, nil, nil, nil, tracepos)
				ent:SetLocalPos(pos)
				ent:SetLocalAngles(ang)

			elseif pl.rgm.IsPhysBone then -- moving physbones
				local isik, iknum = rgm.IsIKBone(self, ent, bone)
				local pos, ang = apart:ProcessMovement(pl.rgmOffsetPos, pl.rgmOffsetAng, eyepos, eyeang, ent, bone, pl.rgmISPos, pl.rgmISDir, 1, snapamount, pl.rgm.StartAngle, nil, nil, nil, tracepos)

				local physcount = ent:GetPhysicsObjectCount() - 1
				if pl.rgm.PropRagdoll then
					physcount = #ent.rgmPRidtoent
					bone = ent.rgmPRenttoid[ent]
				end

				local obj = ent:GetPhysicsObjectNum(pl.rgm.PropRagdoll and 0 or bone)
				if not isik or iknum == 3 or (rotate and (iknum == 1 or iknum == 2)) then
					obj:EnableMotion(true)
					obj:Wake()
					obj:SetPos(pos)
					obj:SetAngles(ang)
					obj:EnableMotion(false)
					obj:Wake()
				elseif iknum == 2 then
					for k, v in pairs(ent.rgmIKChains) do
						if v.knee == bone or (ent.rgmPRidtoent and ent.rgmPRidtoent[v.knee] == ent) then
							local intersect = apart:GetGrabPos(eyepos, eyeang)
							local obj1
							local obj2

							if not pl.rgm.PropRagdoll then
								obj1 = ent:GetPhysicsObjectNum(v.hip)
								obj2 = ent:GetPhysicsObjectNum(v.foot)
							else
								obj1 = ent.rgmPRidtoent[v.hip]:GetPhysicsObjectNum(0)
								obj2 = ent.rgmPRidtoent[v.foot]:GetPhysicsObjectNum(0)
							end

							local kd = (intersect - (obj2:GetPos() + (obj1:GetPos() - obj2:GetPos())))
							kd:Normalize()
							ent.rgmIKChains[k].ikkneedir = kd*1
						end
					end
				end

				local postable = rgm.SetOffsets(self, ent, pl.rgmOffsetTable, {b = bone, p = obj:GetPos(), a = obj:GetAngles()}, pl.rgmAngLocks, pl.rgmPosLocks)

				if not isik or iknum ~= 2 then
					postable[bone].dontset = true
				end

				for i = 0, physcount do
					if postable[i] and not postable[i].dontset then
						local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
						local boneid = not pl.rgm.PropRagdoll and i or 0
						local obj = ent:GetPhysicsObjectNum(boneid)

						obj:EnableMotion(true)
						obj:Wake()
						obj:SetPos(postable[i].pos)
						obj:SetAngles(postable[i].ang)
						obj:EnableMotion(false)
						obj:Wake()
					end

					if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
						for lockent, bones in pairs(postable[i].locked) do
							for j = 0, lockent:GetPhysicsObjectCount() - 1 do
								if bones[j] then
									local obj = lockent:GetPhysicsObjectNum(j)

									obj:EnableMotion(true)
									obj:Wake()
									obj:SetPos(bones[j].pos)
									obj:SetAngles(bones[j].ang)
									obj:EnableMotion(false)
									obj:Wake()
								end
							end
						end
					end
				end

			else -- moving nonphysbones
				local pos, ang = apart:ProcessMovement(pl.rgmOffsetPos, pl.rgmOffsetAng, eyepos, eyeang, ent, bone, pl.rgmISPos, pl.rgmISDir, 2, snapamount, pl.rgm.StartAngle, pl.rgm.NPhysBonePos, pl.rgm.NPhysBoneAng, nil, tracepos) -- if a bone is not physics one, we pass over "start angle" thing

				ent:ManipulateBoneAngles(bone, ang)
				ent:ManipulateBonePosition(bone, pos)

				if ent:GetClass() == "prop_ragdoll" and physmove and pl.rgm.NextPhysBone then -- moving physical if allowed
					local pbone = pl.rgm.NextPhysBone
					local obj = ent:GetPhysicsObjectNum(pbone)

					local opos, oang = obj:GetPos(), obj:GetAngles()
					local nbpos = LocalToWorld(axis.GizmoPos, axis.GizmoAng, opos, oang)
					local _, gizmoang = LocalToWorld(vector_origin, pl.rgm.GizmoAng, vector_origin, oang)

					local npos, nang = LocalToWorld(vector_origin, ang, vector_origin, gizmoang)
					npos = LocalToWorld(pos - pl.rgm.NPhysBonePos, angle_zero, nbpos, axis.GizmoParent)

					local postable = rgm.SetOffsets(self, ent, pl.rgmOffsetTable, {b = pbone, p = obj:GetPos(), a = obj:GetAngles()}, pl.rgmAngLocks, pl.rgmPosLocks, {pos = npos, ang = nang})

					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						if postable[i] and not postable[i].dontset then
							local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
							local boneid = not pl.rgm.PropRagdoll and i or 0
							local obj = ent:GetPhysicsObjectNum(boneid)

							obj:EnableMotion(true)
							obj:Wake()
							obj:SetPos(postable[i].pos)
							obj:SetAngles(postable[i].ang)
							obj:EnableMotion(false)
							obj:Wake()
						end

						if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
							for lockent, bones in pairs(postable[i].locked) do
								for j = 0, lockent:GetPhysicsObjectCount() - 1 do
									if bones[j] then
										local obj = lockent:GetPhysicsObjectNum(j)

										obj:EnableMotion(true)
										obj:Wake()
										obj:SetPos(bones[j].pos)
										obj:SetAngles(bones[j].ang)
										obj:EnableMotion(false)
										obj:Wake()
									end
								end
							end
						end
					end
				end
			end
		else -- scaling
			bone = pl.rgm.Bone
			local prevscale = ent:GetManipulateBoneScale(bone)
			local sc, ang = apart:ProcessMovement(pl.rgmOffsetPos, pl.rgmOffsetAng, eyepos, eyeang, ent, bone, pl.rgmISPos, pl.rgmISDir, 2, snapamount, pl.rgm.StartAngle, pl.rgm.NPhysBonePos, pl.rgm.NPhysBoneAng, pl.rgm.NPhysBoneScale)
			local childbones = pl.rgmBoneChildren

			if sc.x == 0 then sc.x = 0.01 end
			if sc.y == 0 then sc.x = 0.01 end
			if sc.z == 0 then sc.x = 0.01 end

			if axis.scalechildren and not (ent:GetClass() == "ent_advbonemerge") then
				local scalediff = sc - prevscale
				local diff
				local noscale = pl.rgmScaleLocks
				local RecursiveBoneScale

				if axis.smovechildren and childbones and childbones[bone] then
					diff = Vector(sc.x / prevscale.x, sc.y / prevscale.y, sc.z / prevscale.z)

					RecursiveBoneScale = function(ent, bone, scale, diff, ppos, pang)
						if noscale[ent][bone] and not (pl.rgm.Bone == bone) then 
							scale = vector_origin
							diff = VECTOR_SCALEDEF
						end

						local oldscale = ent:GetManipulateBoneScale(bone)
						ent:ManipulateBoneScale(bone, oldscale + scale)

						if childbones[bone] then
							for cbone, tab in pairs(childbones[bone]) do
								local pos = tab.pos
								local bonepos = ent:GetManipulateBonePosition(cbone)
								local newpos = Vector(pos.x * diff.x, pos.y * diff.y, pos.z * diff.z)
								local wpos, wang = nil, nil
								ent:ManipulateBonePosition(cbone, bonepos + (newpos - pos))
								if ent:GetClass() == "prop_ragdoll" then
									wpos, wang = LocalToWorld(newpos, tab.ang, ppos, pang)
									tab.wpos = wpos
								end
								tab.pos = newpos

								RecursiveBoneScale(ent, cbone, scale, diff, wpos, wang)
							end
						end
					end
				else
					RecursiveBoneScale = function(ent, bone, scale)
						if noscale[ent][bone] then return end

						local oldscale = ent:GetManipulateBoneScale(bone)
						ent:ManipulateBoneScale(bone, oldscale + scale)

						for _, cbone in ipairs(ent:GetChildBones(bone)) do
							RecursiveBoneScale(ent, cbone, scale)
						end
					end
				end

				if ent:GetClass() == "prop_ragdoll" then
					local obj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
					if IsValid(obj) then
						local ppos, pang = obj:GetPos(), obj:GetAngles()
						ppos, pang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, ppos, pang)
						RecursiveBoneScale(ent, bone, scalediff, diff, ppos, pang)
					end
				else
					RecursiveBoneScale(ent, bone, scalediff, diff)
				end

			else
				if axis.smovechildren and childbones and childbones[bone] and not (ent:GetClass() == "ent_advbonemerge") then
					local diff = Vector(sc.x / prevscale.x, sc.y / prevscale.y, sc.z / prevscale.z)
					local obj
					local ppos, pang

					if ent:GetClass() == "prop_ragdoll" then
						obj = ent:GetPhysicsObjectNum(pl.rgm.GizmoParentID)
						if IsValid(obj) then
							ppos, pang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, obj:GetPos(), obj:GetAngles())
						end
					end

					for cbone, tab in pairs(childbones[bone]) do
						local pos = tab.pos
						local bonepos = ent:GetManipulateBonePosition(cbone)
						local newpos = Vector(pos.x * diff.x, pos.y * diff.y, pos.z * diff.z)
						local wpos, wang
						ent:ManipulateBonePosition(cbone, bonepos + (newpos - pos))
						if ent:GetClass() == "prop_ragdoll" then
							wpos, wang = LocalToWorld(newpos, tab.ang, ppos, pang)
							tab.wpos = wpos
							rgmAdjustScaleTable(cbone, childbones, wpos, wang)
						end
						tab.pos = newpos
					end
				end

				ent:ManipulateBoneScale(bone, sc)
			end

			if ent:GetClass() == "prop_ragdoll" and physmove and (IsValid(ent:GetPhysicsObjectNum(pl.rgm.PhysBone)) or IsValid(ent:GetPhysicsObjectNum(pl.rgm.NextPhysBone))) and axis.smovechildren then -- moving physical if allowed
				local pbone = pl.rgm.PhysBone
				local prevscale = pl.rgm.NPhysBoneScale
				if pl.rgm.NextPhysBone then
					pbone = pl.rgm.NextPhysBone
				end
				local obj = ent:GetPhysicsObjectNum(pbone)

				local p, a = obj:GetPos(), obj:GetAngles()
				local npos, nang = LocalToWorld(axis.GizmoPos, axis.GizmoAng, p, a)
				local diff = Vector(sc.x / prevscale.x, sc.y / prevscale.y, sc.z / prevscale.z)
				local sbone = pl.rgm.IsPhysBone and {b = pbone, p = p, a = a} or {}
				local postable = rgm.SetScaleOffsets(self, ent, pl.rgmOffsetTable, sbone, diff, pl.rgmPosLocks, pl.rgmScaleLocks, axis.scalechildren, {b = pl.rgm.Bone, pos = npos, ang = nang}, childbones)

				for i = 0, ent:GetPhysicsObjectCount() - 1 do
					if postable[i] and not postable[i].dontset then
						local ent = not pl.rgm.PropRagdoll and ent or ent.rgmPRidtoent[i]
						local boneid = not pl.rgm.PropRagdoll and i or 0
						local obj = ent:GetPhysicsObjectNum(boneid)

						obj:EnableMotion(true)
						obj:Wake()
						obj:SetPos(postable[i].pos)
						obj:SetAngles(postable[i].ang)
						obj:EnableMotion(false)
						obj:Wake()
					end

					if postable[i] and postable[i].locked and ConstrainedAllowed:GetBool() then
						for lockent, bones in pairs(postable[i].locked) do
							for j = 0, lockent:GetPhysicsObjectCount() - 1 do
								if bones[j] then
									local obj = lockent:GetPhysicsObjectNum(j)

									obj:EnableMotion(true)
									obj:Wake()
									obj:SetPos(bones[j].pos)
									obj:SetAngles(bones[j].ang)
									obj:EnableMotion(false)
									obj:Wake()
								end
							end
						end
					end
				end
			end

		end

	end

	local tr = pl:GetEyeTrace()
	if IsValid(tr.Entity) and tr.Entity:GetClass() == "prop_ragdoll" then
		local b = tr.Entity:TranslatePhysBoneToBone(tr.PhysicsBone)
		if pl.rgm.AimedBone ~= b then
			pl.rgm.AimedBone = b
			pl:rgmSyncOne("AimedBone")
		end
	end

	self.LastThink = CurTime()
end

end

end

if CLIENT then

	TOOL.Information = {
		{ name = "left_gizmomode", op = 1 },
		{ name = "right_gizmomode", op = 1 },
		{ name = "reload_gizmomode", op = 1 },
		{ name = "left_default", op = 0 },
		{ name = "info_default", op = 0 },
		{ name = "reload_default", op = 0 },
	}

local RGM_NOTIFY = { -- table with info for messages, true for errors
	[BONELOCK_FAILED] = true,
	[BONELOCK_SUCCESS] = false,
	[BONELOCK_FAILED_NOTPHYS] = true,
	[BONELOCK_FAILED_SAME] = true,
	[ENTLOCK_FAILED_NONPHYS] = true,
	[ENTLOCK_FAILED_NOTALLOWED] = true,
	[ENTLOCK_SUCCESS] = false,
	[ENTSELECT_LOCKRESPONSE] = true,
	[BONE_FROZEN] = false,
	[BONE_UNFROZEN] = false,
}

local pl

hook.Add("InitPostEntity", "rgmSetPlayer", function()
	pl = LocalPlayer()
end)

cvars.AddChangeCallback("ragdollmover_localpos", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(1, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_localang", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(2, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_localoffset", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(3, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_relativerotate", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(4, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_scalechildren", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(5, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_smovechildren", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(6, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_updaterate", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(7, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_unfreeze", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(8, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_snapenable", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(9, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_snapamount", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(10, 4)
	net.SendToServer()
end)

cvars.AddChangeCallback("ragdollmover_physmove", function()
	net.Start("rgmUpdateCCVar")
		net.WriteUInt(11, 4)
	net.SendToServer()
end)

local GizmoScale, GizmoWidth, SkeletonDraw

cvars.AddChangeCallback("ragdollmover_scale", function(convar, old, new)
	GizmoScale = tonumber(new)
end)

cvars.AddChangeCallback("ragdollmover_width", function(convar, old, new)
	GizmoWidth = tonumber(new)
end)

cvars.AddChangeCallback("ragdollmover_drawskeleton", function(convar, old, new)
	SkeletonDraw = tonumber(new) ~= 0
end)

cvars.AddChangeCallback("ragdollmover_fulldisc", function(convar, old, new)
	if not pl or not pl.rgm or not IsValid(pl.rgm.Axis) then return end
	pl.rgm.Axis.fulldisc = tonumber(new) ~= 0
end)

local BONE_PHYSICAL = 1
local BONE_NONPHYSICAL = 2
local BONE_PROCEDURAL = 3
local BONE_PARENTED = 4

local function GetRecursiveBones(ent, boneid, tab, depth)
	for k, v in ipairs(ent:GetChildBones(boneid)) do
		local bone = {id = v, Type = BONE_NONPHYSICAL, parent = boneid, depth = depth + 1}

		if ent:BoneHasFlag(v, 4) then -- BONE_ALWAYS_PROCEDURAL flag
			bone.Type = BONE_PROCEDURAL
		end

		tab[#tab + 1] = bone
		GetRecursiveBones(ent, v, tab, bone.depth)
	end
end

local function GetRecursiveBonesExclusive(ent, boneid, lastvalidbone, tab, physcheck, isphys, depth)
	for k, v in ipairs(ent:GetChildBones(boneid)) do
		local bone = {id = v, Type = BONE_NONPHYSICAL, parent = lastvalidbone, depth = depth + 1}
		local newlastvalid = lastvalidbone

		if ent:BoneHasFlag(v, 4) then -- BONE_ALWAYS_PROCEDURAL flag
			bone.Type = BONE_PROCEDURAL
		end
		if physcheck[v] then
			bone.Type = BONE_PHYSICAL
		end

		if (isphys and bone.Type == BONE_PHYSICAL) or (not isphys and bone.Type ~= BONE_PHYSICAL) then 
			newlastvalid = v
			tab[#tab + 1] = bone
		end

		GetRecursiveBonesExclusive(ent, v, newlastvalid, tab, physcheck, isphys, bone.depth)
	end
end

local function GetRecursiveEntities(ents, parentid, parentent, tab, depth)
	for ent, data in pairs(ents) do
		if data.parent == parentid then
			local entdata = { ent = ent, id = data.id, parent = parentent, depth = depth + 1 }

			tab[#tab + 1] = entdata
			GetRecursiveEntities(ents, entdata.id, ent, tab, entdata.depth)
		end
	end
end

local function GetModelName(ent)
	local name = ent:GetModel()
	local splitname = string.Split(name, "/")
	return splitname[#splitname]
end

local function rgmSendBonePos(pl, ent, boneid)
	if not pl then pl = LocalPlayer() end
	if not pl.rgm then return end

	local gizmopos, gizmoang, gizmoppos, gizmopang
	local axis = pl.rgm.Axis
	if IsValid(ent) and IsValid(axis) and boneid then
		local pos, ang

		local matrix = ent:GetBoneMatrix(boneid)
		local scale = ent:GetManipulateBoneScale(boneid)
		scale = Vector(1 / scale.x, 1 / scale.y, 1 / scale.z) -- Scale and angles are kinda weirdly related with the whole matrix stuff, so we gotta turn scale back to 1 to get precise angle or else it gets messed up (Can't get any angle from 0 scale tho)
		matrix:Scale(scale)
		pos = matrix:GetTranslation()
		ang = matrix:GetAngles()

		if ent:GetClass() == "ent_advbonemerge" and ent.AdvBone_BoneInfo then -- an exception for advanced bonemerged stuff
			local advbones = ent.AdvBone_BoneInfo
			local parent = ent:GetParent()
			if parent.AttachedEntity then parent = parent.AttachedEntity end
			if IsValid(parent) and advbones[boneid].parent and advbones[boneid].parent ~= "" then
				gizmoppos = pos
				gizmopang = ang
			else
				if ent:GetBoneParent(boneid) ~= -1 then
					local matrix = ent:GetBoneMatrix(ent:GetBoneParent(boneid))
					local scale = ent:GetManipulateBoneScale(boneid)
					scale = Vector(1 / scale.x, 1 / scale.y, 1 / scale.z)
					matrix:Scale(scale)
					gizmoppos = matrix:GetTranslation()
					gizmopang = matrix:GetAngles()
				else
					gizmoppos = parent:GetPos()
					gizmopang = ent:GetAngles()
				end
			end
		elseif ent:GetBoneParent(boneid) ~= -1 then
			local matrix = ent:GetBoneMatrix(ent:GetBoneParent(boneid))
			local scale = ent:GetManipulateBoneScale(boneid)
			scale = Vector(1 / scale.x, 1 / scale.y, 1 / scale.z)
			matrix:Scale(scale)
			gizmoppos = matrix:GetTranslation()
			gizmopang = matrix:GetAngles()
		else
			gizmoppos = ent:GetPos()
			gizmopang = ent:GetAngles()
		end

		gizmopos = pos
		gizmoang = ang
	else
		gizmopos = vector_origin
		gizmoang = angle_zero
		gizmoppos = vector_origin
		gizmopang = angle_zero
	end

	local childbones = {}
	local count = 1
	local function RecursiveGrabChildBones(b, tab, ent)
		for k, bone in ipairs(ent:GetChildBones(b)) do
			tab[count] = {}
			tab[count].id = bone
			tab[count].parent = b
			local matrix = ent:GetBoneMatrix(bone)
			local bonepos = matrix:GetTranslation()
			local boneang = matrix:GetAngles()
			tab[count].pos, tab[count].ang = bonepos, boneang
			count = count + 1
			RecursiveGrabChildBones(bone, tab, ent)
		end
	end

	RecursiveGrabChildBones(boneid, childbones, ent)

	net.Start("rgmSendBonePos")
		net.WriteVector(gizmopos)
		net.WriteAngle(gizmoang)
		net.WriteVector(gizmoppos)
		net.WriteAngle(gizmopang)

		net.WriteUInt(#childbones, 10)
		for _, data in ipairs(childbones) do
			net.WriteUInt(data.id, 10)
			net.WriteUInt(data.parent, 10)
			net.WriteVector(data.pos)
			net.WriteAngle(data.ang)
		end
	net.SendToServer()
end

local function RGMPrepareOffsets()
	if not pl or not pl.rgm or not IsValid(pl.rgm.Entity) or pl.rgm.Entity:GetClass() ~= "prop_ragdoll" then return end
	net.Start("rgmPrepareOffsets")
	net.SendToServer()
end

local function RGMClearOffsets()
	if not pl or not pl.rgm or not IsValid(pl.rgm.Entity) or pl.rgm.Entity:GetClass() ~= "prop_ragdoll" then return end
	net.Start("rgmClearOffsets")
	net.SendToServer()
end

local function CCheckBox(cpanel, text, cvar)
	local CB = vgui.Create("DCheckBoxLabel", cpanel)
	CB:SetText(text)
	CB:SetConVar(cvar)
	CB:SetDark(true)
	cpanel:AddItem(CB)
	return CB
end
local function CNumSlider(cpanel, text, cvar, min, max, dec)
	local SL = vgui.Create("DNumSlider", cpanel)
	SL:SetText(text)
	SL:SetDecimals(dec)
	SL:SetMinMax(min, max)
	SL:SetConVar(cvar)
	SL:SetDark(true)

	cpanel:AddItem(SL)
	return SL
end

local ManipSliderUpdating = false

local function CManipSlider(cpanel, text, mode, axis, min, max, dec, textentry)
	local slider = vgui.Create("DNumSlider", cpanel)
	local round = math.Round
	slider:SetText(text)
	slider:SetDecimals(dec)
	slider:SetMinMax(min, max)
	slider:SetDark(true)
	slider:SetValue(0)
	if mode == 3 then
		slider:SetDefaultValue(1)
	else
		slider:SetDefaultValue(0)
	end

	local scratchpressold, textareafocusold, sliderpressold = slider.Scratch.OnMousePressed, slider.TextArea.OnGetFocus, slider.Slider.OnMousePressed

	slider.Scratch.OnMousePressed = function(self, mc)
		scratchpressold(self, mc)
		RGMPrepareOffsets()
	end

	slider.TextArea.OnGetFocus = function(self)
		textareafocusold(self)
		RGMPrepareOffsets()
	end

	slider.Slider.OnMousePressed = function(self, mc)
		sliderpressold(self, mc)
		RGMPrepareOffsets()
	end

	local scratchrelaseold, textarealosefocusold, sliderreleaseold = slider.Scratch.OnMouseReleased, slider.TextArea.OnLoseFocus, slider.Slider.OnMouseReleased

	slider.Scratch.OnMouseReleased = function(self, mc)
		scratchrelaseold(self, mc)
		RGMClearOffsets()
	end

	slider.TextArea.OnLoseFocus = function(self)
		textarealosefocusold(self)
		RGMClearOffsets()
	end

	slider.Slider.OnMouseReleased = function(self, mc)
		sliderreleaseold(self, mc)
		RGMClearOffsets()
	end

	function slider:OnValueChanged(value)
		if ManipSliderUpdating then return end
		ManipSliderUpdating = true

		if mode == 3 and value == 0 then value = 0.01 end

		net.Start("rgmAdjustBone")
		net.WriteInt(mode, 3)
		net.WriteInt(axis, 3)
		net.WriteFloat(value)
		net.SendToServer()

		textentry:SetValue(round(textentry.Sliders[1]:GetValue(), 2) .. " " .. round(textentry.Sliders[2]:GetValue(), 2) .. " " .. round(textentry.Sliders[3]:GetValue(), 2))
		ManipSliderUpdating = false
	end

	cpanel:AddItem(slider)

	return slider
end
local function CManipEntry(cpanel, mode)
	local entry = vgui.Create("DTextEntry", cpanel, slider1, slider2, slider3)
	entry:SetValue("0 0 0")
	entry:SetUpdateOnType(true)
	entry.OnValueChange = function(self, value)
		if ManipSliderUpdating then return end
		ManipSliderUpdating = true

		local values = string.Explode(" ", value)
		for i = 1, 3 do
			if values[i] and tonumber(values[i]) and IsValid(entry.Sliders[i]) then
				entry.Sliders[i]:SetValue(tonumber(values[i]))

				if mode == 3 and tonumber(values[i]) == 0 then values[i] = 0.01 end

				net.Start("rgmAdjustBone")
				net.WriteInt(mode, 3)
				net.WriteInt(i, 3)
				net.WriteFloat(tonumber(values[i]))
				net.SendToServer()
			end
		end
		ManipSliderUpdating = false
	end

	local textfocusold = entry.OnGetFocus

	entry.OnGetFocus = function(self)
		textfocusold(self)
		RGMPrepareOffsets()
	end

	local textlosefocusold = entry.OnLoseFocus

	entry.OnLoseFocus = function(self)
		textlosefocusold(self)
		RGMClearOffsets()
	end

	entry.Sliders = {}
	cpanel:AddItem(entry)
	return entry
end
local function CGizmoSlider(cpanel, text, axis, min, max, dec)
	local slider = vgui.Create("DNumSlider", cpanel)
	slider:SetText(text)
	slider:SetDecimals(dec)
	slider:SetMinMax(min, max)
	slider:SetDark(true)
	slider:SetValue(0)
	slider:SetDefaultValue(0)

	function slider:OnValueChanged(value)
		net.Start("rgmGizmoOffset")
			net.WriteUInt(axis, 2)
			net.WriteFloat(value)
		net.SendToServer()
	end

	cpanel:AddItem(slider)
	return slider
end
local function CButton(cpanel, text, func, arg)
	local butt = vgui.Create("DButton", cpanel)
	butt:SetText(text)
	function butt:DoClick()
		func(arg)
	end
	cpanel:AddItem(butt)
	return butt
end
local function CCol(cpanel, text, notexpanded)
	local cat = vgui.Create("DCollapsibleCategory", cpanel)
	cat:SetExpanded(1)
	cat:SetLabel(text)
	cpanel:AddItem(cat)
	local col = vgui.Create("DPanelList")
	col:SetAutoSize(true)
	col:SetSpacing(5)
	col:EnableHorizontal(false)
	col:EnableVerticalScrollbar(true)
	col.Paint = function()
		surface.DrawRect(0, 0, 500, 500)
	end
	cat:SetContents(col)
	cat:SetExpanded(not notexpanded)
	return col, cat
end
local function CBinder(cpanel)
	local parent = vgui.Create("Panel", cpanel)
	cpanel:AddItem(parent)

	local bindrot = vgui.Create("DBinder", parent)
	bindrot.Label = vgui.Create("DLabel", parent)
	bindrot:SetConVar("ragdollmover_rotatebutton")
	bindrot:SetSize(100, 50)

	bindrot.Label:SetText("#tool.ragdollmover.bindrot")
	bindrot.Label:SetDark(true)
	bindrot.Label:SizeToContents()

	function bindrot:OnChange(keycode)
		net.Start("rgmSetToggleRot")
			net.WriteInt(keycode, 8)
		net.SendToServer()
	end

	local bindsc = vgui.Create("DBinder", parent)
	bindsc.Label = vgui.Create("DLabel", parent)
	bindsc:SetConVar("ragdollmover_scalebutton")
	bindsc:SetSize(100, 50)

	bindsc.Label:SetText("#tool.ragdollmover.bindscale")
	bindsc.Label:SetDark(true)
	bindsc.Label:SizeToContents()

	function bindsc:OnChange(keycode)
		net.Start("rgmSetToggleScale")
			net.WriteInt(keycode, 8)
		net.SendToServer()
	end

	local rotw, scw = bindrot.Label:GetWide(), bindsc.Label:GetWide()

	parent.PerformLayout = function()
		parent:SetHeight(80)

		bindrot:SetPos(parent:GetWide() / 2 - 100 - 5 - 30 * (parent:GetWide() / 217 - 1), 25)
		bindrot.Label:SetPos(bindrot:GetX() + 50 - rotw / 2, 0)
		bindrot.Label:SetWidth(parent:GetWide() / 2 - bindrot.Label:GetX())

		bindsc:SetPos(parent:GetWide() / 2 + 5 + 30 * (parent:GetWide() / 217 - 1), 25)
		bindsc.Label:SetPos(bindsc:GetX() + 50 - scw / 2, 0)
		bindsc.Label:SetWidth(parent:GetWide() - bindsc.Label:GetX())
	end
end

local AdditionalIKs = {
	"ragdollmover_ik_chain_1",
	"ragdollmover_ik_chain_2",
	"ragdollmover_ik_chain_3",
	"ragdollmover_ik_chain_4",
	"ragdollmover_ik_chain_5",
	"ragdollmover_ik_chain_6"
}

local function RGMSelectAllIK()
	local ik1, ik2, ik3, ik4 = GetConVar("ragdollmover_ik_leg_L"):GetBool(), GetConVar("ragdollmover_ik_leg_R"):GetBool(), GetConVar("ragdollmover_ik_hand_L"):GetBool(), GetConVar("ragdollmover_ik_hand_R"):GetBool()

	if ik1 && ik2 && ik3 && ik4 then
		RunConsoleCommand("ragdollmover_ik_hand_L", 0)
		RunConsoleCommand("ragdollmover_ik_hand_R", 0)
		RunConsoleCommand("ragdollmover_ik_leg_L", 0)
		RunConsoleCommand("ragdollmover_ik_leg_R", 0)
	else
		RunConsoleCommand("ragdollmover_ik_hand_L", 1)
		RunConsoleCommand("ragdollmover_ik_hand_R", 1)
		RunConsoleCommand("ragdollmover_ik_leg_L", 1)
		RunConsoleCommand("ragdollmover_ik_leg_R", 1)
	end
end

local function CBAdditionalIKs(cpanel, text)
	local butt = vgui.Create("DButton", cpanel)
	butt:SetText(text)
	function butt:DoClick()
		local menu = DermaMenu(false, cpanel)
		local panel = vgui.Create("Panel")
		panel:SetSize(100, 125)
		panel.iks = {}

		for i = 1, 6 do
			panel.iks[i] = vgui.Create("DCheckBoxLabel", panel)
			panel.iks[i]:SetText(language.GetPhrase("tool.ragdollmover.ikchain") .. " " ..i)
			panel.iks[i]:SetDark(true)
			panel.iks[i]:SetConVar(AdditionalIKs[i])
			panel.iks[i]:SetSize(90, 15)
			panel.iks[i]:SetPos(5, 5 + 20*(i - 1))
		end

		menu:AddPanel(panel)
		menu:Open()
	end
	cpanel:AddItem(butt)

	return butt
end

local function RGMResetGizmo()
	if not pl.rgm then return end
	net.Start("rgmResetGizmo")
	net.SendToServer()
end

local function RGMGizmoMode()
	if not pl.rgm then return end
	net.Start("rgmOperationSwitch")
	net.SendToServer()
end

local function RGMResetAllBones()
	if not pl.rgm or not pl.rgm.Entity then return end

	net.Start("rgmResetAllBones")
		net.WriteEntity(pl.rgm.Entity)
	net.SendToServer()
end

local function AddHBar(self) -- There is no horizontal scrollbars in gmod, so I guess we'll override vertical one from GMod - I think this is incorrect now, but I'll keep it
	self.HBar = vgui.Create("DVScrollBar")

	self.HBar.btnUp.Paint = function(panel, w, h) derma.SkinHook("Paint", "ButtonLeft", panel, w, h) end
	self.HBar.btnDown.Paint = function(panel, w, h) derma.SkinHook("Paint", "ButtonRight", panel, w, h) end

	self.PanelWidth = 100
	self.LastWidth = 1

	self.HBar.SetScroll = function(self, scrll)
		if (not self.Enabled) then self.Scroll = 0 return end

		self.Scroll = math.Clamp( scrll, 0, self.CanvasSize )
		self:InvalidateLayout()

		local func = self:GetParent().OnHScroll
		if func then
			func(self:GetParent(), self:GetOffset())
		end
	end

	self.HBar.OnMousePressed = function(self)
		local x, y = self:CursorPos()
		local PageSize = self.BarSize

		if (x > self.btnGrip.x) then
			self:SetScroll(self:GetScroll() + PageSize)
		else
			self:SetScroll(self:GetScroll() - PageSize)
		end
	end

	self.HBar.OnCursorMoved = function(self, x, y)
		if (not self.Enabled) then return end
		if (not self.Dragging) then return end

		local x, y = self:ScreenToLocal(gui.MouseX(), 0)

		x = x - self.btnUp:GetWide()
		x = x - self.HoldPos

		local BtnHeight = self:GetTall()
		if (self:GetHideButtons()) then BtnHeight = 0 end

		local TrackSize = self:GetWide() - BtnHeight * 2 - self.btnGrip:GetWide()

		x = x / TrackSize

		self:SetScroll(x * self.CanvasSize)
	end

	self.HBar.Grip = function(self)
		if (!self.Enabled) then return end
		if (self.BarSize == 0) then return end

		self:MouseCapture(true)
		self.Dragging = true

		local x, y = self.btnGrip:ScreenToLocal(gui.MouseX(), 0)
		self.HoldPos = x

		self.btnGrip.Depressed = true
	end

	self.HBar.PerformLayout = function(self)
		local Tall = self:GetTall()
		local BtnHeight = Tall
		if (self:GetHideButtons()) then BtnHeight = 0 end
		local Scroll = self:GetScroll() / self.CanvasSize
		local BarSize = math.max(self:BarScale() * (self:GetWide() - (BtnHeight * 2)), 10)
		local Track = self:GetWide() - (BtnHeight * 2) - BarSize
		Track = Track + 1

		Scroll = Scroll * Track

		self.btnGrip:SetPos(BtnHeight + Scroll, 0)
		self.btnGrip:SetSize(BarSize, Tall)

		if (BtnHeight > 0) then
			self.btnUp:SetPos(0, 0)
			self.btnUp:SetSize(BtnHeight, Tall)

			self.btnDown:SetPos(self:GetWide() - BtnHeight, 0)
			self.btnDown:SetSize(BtnHeight, Tall)

			self.btnUp:SetVisible( true )
			self.btnDown:SetVisible( true )
		else
			self.btnUp:SetVisible( false )
			self.btnDown:SetVisible( false )
			self.btnDown:SetSize(BtnHeight, Tall)
			self.btnUp:SetSize(BtnHeight, Tall)
		end
	end

	self.OnVScroll = function(self, iOffset)
		local x = self.pnlCanvas:GetPos()
		self.pnlCanvas:SetPos(x, iOffset)
	end

	self.OnHScroll = function(self, iOffset)
		local _, y = self.pnlCanvas:GetPos()
		self.pnlCanvas:SetPos(iOffset, y)
	end

	self.PerformLayoutInternal = function(self)
		local HTall, VTall = self:GetTall(), self.pnlCanvas:GetTall()
		local HWide, VWide = self:GetWide(), self.PanelWidth
		local XPos, YPos = 0, 0

		self:Rebuild()

		self.VBar:SetUp(self:GetTall(), self.pnlCanvas:GetTall())
		self.HBar:SetUp(self:GetWide(), self.pnlCanvas:GetWide())
		YPos = self.VBar:GetOffset()
		XPos = self.HBar:GetOffset()

		if (self.VBar.Enabled) then VWide = VWide - self.VBar:GetWide() end
		if (self.HBar.Enabled) then HTall = HTall - self.HBar:GetTall() end

		self.pnlCanvas:SetPos(XPos, YPos)
		self.pnlCanvas:SetSize(VWide, HTall)

		self:Rebuild()

		if (HWide ~= self.LastWidth) then
			self.HBar:SetScroll(self.HBar:GetScroll())
		end

		if (VTall ~= self.pnlCanvas:GetTall()) then
			self.VBar:SetScroll(self.VBar:GetScroll())
		end

		self.LastWidth = HWide
	end

	self.PerformLayout = function(self)
		self:PerformLayoutInternal()
	end

	self.UpdateWidth = function(self, newwidth)
		self.PanelWidth = newwidth
		self:InvalidateLayout()
	end
end

local BoneTypeSort = {
	{ Icon = "icon16/brick.png", ToolTip = "#tool.ragdollmover.physbone" },
	{ Icon = "icon16/connect.png", ToolTip = "#tool.ragdollmover.nonphysbone" },
	{ Icon = "icon16/error.png", ToolTip = "#tool.ragdollmover.proceduralbone" },
}


local BonePanel, EntPanel, ConEntPanel
local EnableIKButt
local Pos1, Pos2, Pos3, Rot1, Rot2, Rot3, Scale1, Scale2, Scale3, Entry1, Entry2, Entry3
local Gizmo1, Gizmo2, Gizmo3
local nodes, entnodes, conentnodes
local HoveredBone, HoveredEntBone, HoveredEnt
local Col4
local LockMode, LockTo = false, { id = nil, ent = nil }
local IsPropRagdoll, TreeEntities = false, {}
local ScaleLocks = {}

cvars.AddChangeCallback("ragdollmover_ik_hand_L", function(convar, old, new)
	if not IsValid(EnableIKButt) then return end

	if tobool(new) and GetConVar("ragdollmover_ik_hand_R"):GetBool() and GetConVar("ragdollmover_ik_leg_L"):GetBool() and GetConVar("ragdollmover_ik_leg_R"):GetBool() then
		EnableIKButt:SetText("#tool.ragdollmover.ikalloff")
	else
		EnableIKButt:SetText("#tool.ragdollmover.ikallon")
	end
end)

cvars.AddChangeCallback("ragdollmover_ik_hand_R", function(convar, old, new)
	if not IsValid(EnableIKButt) then return end

	if tobool(new) and GetConVar("ragdollmover_ik_hand_L"):GetBool() and GetConVar("ragdollmover_ik_leg_L"):GetBool() and GetConVar("ragdollmover_ik_leg_R"):GetBool() then
		EnableIKButt:SetText("#tool.ragdollmover.ikalloff")
	else
		EnableIKButt:SetText("#tool.ragdollmover.ikallon")
	end
end)

cvars.AddChangeCallback("ragdollmover_ik_leg_L", function(convar, old, new)
	if not IsValid(EnableIKButt) then return end

	if tobool(new) and GetConVar("ragdollmover_ik_hand_R"):GetBool() and GetConVar("ragdollmover_ik_hand_L"):GetBool() and GetConVar("ragdollmover_ik_leg_R"):GetBool() then
		EnableIKButt:SetText("#tool.ragdollmover.ikalloff")
	else
		EnableIKButt:SetText("#tool.ragdollmover.ikallon")
	end
end)

cvars.AddChangeCallback("ragdollmover_ik_leg_R", function(convar, old, new)
	if not IsValid(EnableIKButt) then return end

	if tobool(new) and GetConVar("ragdollmover_ik_hand_R"):GetBool() and GetConVar("ragdollmover_ik_leg_L"):GetBool() and GetConVar("ragdollmover_ik_hand_L"):GetBool() then
		EnableIKButt:SetText("#tool.ragdollmover.ikalloff")
	else
		EnableIKButt:SetText("#tool.ragdollmover.ikallon")
	end
end)

local function SetBoneNodes(bonepanel, sortedbones)
	nodes = {}

	local width = 0

	for i, entdata in ipairs(sortedbones) do
		local ent = entdata.ent
		nodes[ent] = { id = entdata.id, parent = entdata.parent }

		for k, v in ipairs(entdata) do
			local text1 = ent:GetBoneName(v.id)

			if nodes[ent].parent then
				nodes[ent][v.id] = nodes[nodes[ent].parent][0]:AddNode(text1)
			elseif v.parent then
				nodes[ent][v.id] = nodes[ent][v.parent]:AddNode(text1)
			else
				nodes[ent][v.id] = bonepanel:AddNode(text1)
			end

			nodes[ent][v.id].Type = v.Type
			nodes[ent][v.id]:SetExpanded(true)

			if ScaleLocks[ent][v.id] then
				nodes[ent][v.id]:SetIcon("icon16/lightbulb.png")
				nodes[ent][v.id].Label:SetToolTip("#tool.ragdollmover.lockedscale")
				nodes[ent][v.id].scllock = true
			else
				nodes[ent][v.id]:SetIcon(BoneTypeSort[v.Type].Icon)
				nodes[ent][v.id].Label:SetToolTip(BoneTypeSort[v.Type].ToolTip)
			end

			nodes[ent][v.id].DoClick = function()
				if not LockMode then
					net.Start("rgmSelectBone")
						net.WriteEntity(ent)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				else
					if LockMode == 1 then
						net.Start("rgmLockToBone")
							net.WriteEntity(ent)
							net.WriteUInt(v.id, 10)
							net.WriteEntity(LockTo.ent)
							net.WriteUInt(LockTo.id, 10)
						net.SendToServer()

						if nodes[LockTo.ent][LockTo.id].poslock or nodes[LockTo.ent][LockTo.id].anglock then
							nodes[LockTo.ent][LockTo.id]:SetIcon("icon16/lock.png")
							nodes[LockTo.ent][LockTo.id].Label:SetToolTip("#tool.ragdollmover.lockedbone")
						elseif nodes[LockTo.ent][LockTo.id].scllock then
							nodes[LockTo.ent][LockTo.id]:SetIcon("icon16/lightbulb.png")
							nodes[LockTo.ent][LockTo.id].Label:SetToolTip("#tool.ragdollmover.lockedscale")
						else
							nodes[LockTo.ent][LockTo.id]:SetIcon(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].Icon)
							nodes[LockTo.ent][LockTo.id].Label:SetToolTip(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].ToolTip)
						end
					elseif LockMode == 2 then
						net.Start("rgmLockConstrained")
							net.WriteEntity(ent)
							net.WriteEntity(LockTo.id) -- In this case it isn't really "LockTo", more of "LockThis" but I was lazy so used same variables. Probably once I get to C++ stuff trying to do the same thing would be baaad
							net.WriteBool(true)
							net.WriteUInt(v.id, 8)
						net.SendToServer()

						conentnodes[LockTo.id]:SetIcon("icon16/brick_link.png")
						conentnodes[LockTo.id].Label:SetToolTip(false)
					end

					LockMode = false
					LockTo = { id = nil, ent = nil }
				end

			end

			nodes[ent][v.id].DoRightClick = function()
				local bonemenu = DermaMenu(false, bonepanel)
				local resetmenu = bonemenu:AddSubMenu("#tool.ragdollmover.resetmenu")

				local option = resetmenu:AddOption("#tool.ragdollmover.reset", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetAll")
						net.WriteEntity(ent)
						net.WriteUInt(v.id, 10)
						net.WriteBool(false)
					net.SendToServer()
				end)
				option:SetIcon("icon16/connect.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetpos", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetPos")
						net.WriteEntity(ent)
						net.WriteBool(false)
						net.WriteUInt(v.id, 10) -- with SFM studiomdl, it seems like upper limit for bones is 256. Used 10 bits in case if there was 512 https://developer.valvesoftware.com/wiki/Skeleton
					net.SendToServer()
				end)
				option:SetIcon("icon16/connect.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetrot", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetAng")
						net.WriteEntity(ent)
						net.WriteBool(false)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/connect.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetscale", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetScale")
						net.WriteEntity(ent)
						net.WriteBool(false)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/connect.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetchildren", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetAll")
						net.WriteEntity(ent)
						net.WriteUInt(v.id, 10)
						net.WriteBool(true)
					net.SendToServer()
				end)
				option:SetIcon("icon16/bricks.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetposchildren", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetPos")
						net.WriteEntity(ent)
						net.WriteBool(true)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/bricks.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetrotchildren", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetAng")
						net.WriteEntity(ent)
						net.WriteBool(true)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/bricks.png")

				option = resetmenu:AddOption("#tool.ragdollmover.resetscalechildren", function()
					if not IsValid(ent) then return end
					net.Start("rgmResetScale")
						net.WriteEntity(ent)
						net.WriteBool(true)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/bricks.png")

				local scalezeromenu = bonemenu:AddSubMenu("#tool.ragdollmover.scalezero")

				option = scalezeromenu:AddOption("#tool.ragdollmover.bone", function()
					if not IsValid(ent) then return end
					net.Start("rgmScaleZero")
						net.WriteEntity(ent)
						net.WriteBool(false)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/connect.png")

				option = scalezeromenu:AddOption("#tool.ragdollmover.bonechildren", function()
					if not IsValid(ent) then return end
					net.Start("rgmScaleZero")
						net.WriteEntity(ent)
						net.WriteBool(true)
						net.WriteUInt(v.id, 10)
					net.SendToServer()
				end)
				option:SetIcon("icon16/bricks.png")

				bonemenu:AddSpacer()

				if nodes[ent][v.id].bonelock then

					option = bonemenu:AddOption("#tool.ragdollmover.unlockbone", function()
						if not IsValid(ent) then return end
						net.Start("rgmUnlockToBone")
							net.WriteEntity(ent)
							net.WriteUInt(v.id, 10)
						net.SendToServer()
					end)

					bonemenu:AddSpacer()
				elseif nodes[ent][v.id].Type == BONE_PHYSICAL and IsValid(ent) and ( ent:GetClass() == "prop_ragdoll" or IsPropRagdoll ) then

					option = bonemenu:AddOption(nodes[ent][v.id].poslock and "#tool.ragdollmover.unlockpos" or "#tool.ragdollmover.lockpos", function()
						if not IsValid(ent) then return end
						net.Start("rgmLockBone")
							net.WriteEntity(ent)
							net.WriteUInt(1, 2)
							net.WriteUInt(v.id, 10)
						net.SendToServer()
					end)
					option:SetIcon(nodes[ent][v.id].poslock and "icon16/lock.png" or "icon16/brick.png")

					option = bonemenu:AddOption(nodes[ent][v.id].anglock and "#tool.ragdollmover.unlockang" or "#tool.ragdollmover.lockang", function()
						if not IsValid(ent) then return end
						net.Start("rgmLockBone")
							net.WriteEntity(ent)
							net.WriteUInt(2, 2)
							net.WriteUInt(v.id, 10)
						net.SendToServer()
					end)
					option:SetIcon(nodes[ent][v.id].anglock and "icon16/lock.png" or "icon16/brick.png")

					option = bonemenu:AddOption("#tool.ragdollmover.lockbone", function()
						if not IsValid(ent) then return end

						if LockMode == 1 then
							nodes[LockTo.ent][LockTo.id]:SetIcon(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].Icon)
							nodes[LockTo.ent][LockTo.id].Label:SetToolTip(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].ToolTip)
						elseif LockMode == 2 then
							conentnodes[LockTo.id]:SetIcon("icon16/brick_link.png")
							conentnodes[LockTo.id].Label:SetToolTip(false)
						end

						LockMode = 1
						LockTo = { id = v.id, ent = ent }

						surface.PlaySound("buttons/button9.wav")
						nodes[ent][v.id]:SetIcon("icon16/brick_add.png")
						nodes[ent][v.id].Label:SetToolTip("#tool.ragdollmover.bonetolock")
					end)
					option:SetIcon("icon16/lock.png")

					bonemenu:AddSpacer()
				end

				option = bonemenu:AddOption(nodes[ent][v.id].scllock and "#tool.ragdollmover.unlockscale" or "#tool.ragdollmover.lockscale", function()
						if not IsValid(ent) then return end
						net.Start("rgmLockBone")
							net.WriteEntity(ent)
							net.WriteUInt(3, 2)
							net.WriteUInt(v.id, 10)
						net.SendToServer()
					end)
				option:SetIcon(nodes[ent][v.id].scllock and "icon16/lightbulb.png" or "icon16/connect.png")

				if nodes[ent][v.id].Type == BONE_PHYSICAL and IsValid(ent) and ( ent:GetClass() == "prop_ragdoll" or IsPropRagdoll ) then
					option = bonemenu:AddOption("#tool.ragdollmover.freezebone", function()
						if not IsValid(ent) then return end

						net.Start("rgmBoneFreezer")
							net.WriteEntity(ent)
							net.WriteUInt(v.id, 10)
						net.SendToServer()
					end)
					option:SetIcon("icon16/transmit_blue.png")
				end

				bonemenu:AddOption("#tool.ragdollmover.putgizmopos", function()
					if not IsValid(ent) then return end

					local bone = v.id
					local pos = ent:GetBonePosition(bone)
					if pos == ent:GetPos() then
						local matrix = ent:GetBoneMatrix(bone)
						pos = matrix:GetTranslation()
					end

					net.Start("rgmSetGizmoToBone")
						net.WriteVector(pos)
					net.SendToServer()
				end)

				local x = bonepanel:LocalToScreen(5, 0)

				bonemenu:Open(x)
			end

			nodes[ent][v.id].Label.OnCursorEntered = function()
				HoveredBone = v.id
				HoveredEntBone = ent
			end

			nodes[ent][v.id].Label.OnCursorExited = function()
				HoveredBone = nil
				HoveredEntBone = nil
			end

			local xsize = nodes[ent][v.id].Label:GetTextSize()
			local currentwidth = xsize + ((v.depth + entdata.depth - 1) * 17)
			if currentwidth > width then
				width = currentwidth
			end
		end
	end

	bonepanel:UpdateWidth(width + 8 + 32 + 16)
end

local function RGMBuildBoneMenu(ents, selectedent, bonepanel)
	bonepanel:Clear()
	if not IsValid(selectedent) then return end
	local sortedbones = {}
	local count = 0

	for ent, data in pairs(ents) do
		if not IsValid(ent) then continue end

		if not data.parent then
			local entdata = { ent = ent, id = data.id, depth = 1 }
			table.insert(sortedbones, entdata)

			GetRecursiveEntities(ents, entdata.id, ent, sortedbones, entdata.depth)
		end
	end

	for id, entdata in ipairs(sortedbones) do
		local ent = entdata.ent
		local num = ent:GetBoneCount() - 1 -- first we find all rootbones and their children
		for v = 0, num do
			if ent:GetBoneName(v) == "__INVALIDBONE__" then continue end

			if ent:GetBoneParent(v) == -1 then
				local bone = { id = v, Type = BONE_NONPHYSICAL, depth = 1 }
				if ent:BoneHasFlag(v, 4) then -- BONE_ALWAYS_PROCEDURAL flag
					bone.Type = BONE_PROCEDURAL
				end

				table.insert(entdata, bone)
				GetRecursiveBones(ent, v, entdata, bone.depth)
			end
		end
		count = count + 1
	end

	SetBoneNodes(bonepanel, sortedbones)

	net.Start("rgmAskForPhysbones")
		net.WriteUInt(count, 13)
		for ent, _ in pairs(ents) do
			net.WriteEntity(ent)
		end
	net.SendToServer()

	for ent, _ in pairs(ents) do
		if ent:IsEffectActive(EF_BONEMERGE) or ent:GetClass() == "ent_advbonemerge" then
			net.Start("rgmAskForParented")
				net.WriteUInt(count, 13)
				for ent, _ in pairs(ents) do
					net.WriteEntity(ent)
				end
			net.SendToServer()
			break
		end
	end
end

local function ShowOnlyPhysNodes(ent, bonepanel)
	bonepanel:Clear()
	if not IsValid(ent) then return end
	local count = 0

	for ent, data in pairs(TreeEntities) do
		count = count + 1
	end

	net.Start("rgmAskForNodeUpdatePhysics")
		net.WriteBool(true)
		net.WriteUInt(count, 13)

		for ent, _ in pairs(TreeEntities) do
			net.WriteEntity(ent)
		end
	net.SendToServer()
end

local function ShowOnlyNonPhysNodes(ent, bonepanel)
	bonepanel:Clear()
	if not IsValid(ent) then return end
	local count = 0

	for ent, data in pairs(TreeEntities) do
		count = count + 1
	end

	net.Start("rgmAskForNodeUpdatePhysics")
		net.WriteBool(false)
		net.WriteUInt(count, 13)

		for ent, _ in pairs(TreeEntities) do
			net.WriteEntity(ent)
		end
	net.SendToServer()
end

local function UpdateBoneNodes(bonepanel, physids, isphys)
	local sortedbones = {}
	local count = 0

	for ent, data in pairs(TreeEntities) do
		if not IsValid(ent) then continue end

		if not data.parent then
			local entdata = { ent = ent, id = data.id, depth = 1 }
			table.insert(sortedbones, entdata)

			GetRecursiveEntities(TreeEntities, entdata.id, ent, sortedbones, entdata.depth)
		end
	end

	for id, entdata in ipairs(sortedbones) do
		local ent = entdata.ent

		local num = ent:GetBoneCount() - 1
		for v = 0, num do
			if ent:GetBoneName(v) == "__INVALIDBONE__" then continue end

			if ent:GetBoneParent(v) == -1 then
				local bone = { id = v, Type = BONE_NONPHYSICAL, depth = 1 }
				if ent:BoneHasFlag(v, 4) then
					bone.Type = BONE_PROCEDURAL
				end
				if physids[ent][v] then
					bone.Type = BONE_PHYSICAL
				end

				table.insert(entdata, bone)
				GetRecursiveBonesExclusive(ent, v, v, entdata, physids[ent], isphys, bone.depth)
			end
		end
		count = count + 1
	end

	SetBoneNodes(bonepanel, sortedbones)

	if isphys then
		net.Start("rgmAskForPhysbones")
			net.WriteUInt(count, 13)
			for ent, _ in pairs(TreeEntities) do
				net.WriteEntity(ent)
			end
		net.SendToServer()
	end

	for ent, _ in pairs(TreeEntities) do
		if ent:IsEffectActive(EF_BONEMERGE) then
			net.Start("rgmAskForParented")
				net.WriteUInt(count, 13)
				for ent, _ in pairs(TreeEntities) do
					net.WriteEntity(ent)
				end
			net.SendToServer()
			break
		end
	end
end

local function RGMBuildEntMenu(ents, children, entpanel)
	entpanel:Clear()
	local width = 0

	entnodes = {}

	for parent, entdata in pairs(ents) do
		if not IsValid(parent) then continue end

		entnodes[parent] = entpanel:AddNode(GetModelName(parent))
		entnodes[parent]:SetExpanded(true)

		entnodes[parent].DoClick = function()
			net.Start("rgmSelectEntity")
				net.WriteEntity(parent)
				net.WriteBool(false)
			net.SendToServer()
		end

		entnodes[parent].Label.OnCursorEntered = function()
			HoveredEnt = parent
		end

		entnodes[parent].Label.OnCursorExited = function()
			HoveredEnt = nil
		end

		local xsize = entnodes[parent].Label:GetTextSize() + 17
		if xsize > width then
			width = xsize
		end

		local sortchildren = {depth = 1}

		local function RecursiveChildrenSort(ent, sorttable, depth)
			for k, v in ipairs(children[parent]) do
				if v:GetParent() ~= ent then continue end
				table.insert(sorttable, v)
				sorttable[v] = {}
				sorttable[v].depth = depth + 1
				RecursiveChildrenSort(v, sorttable[v], depth + 1)
			end
		end

		RecursiveChildrenSort(parent, sortchildren, sortchildren.depth)

		local function MakeChildrenList(parent, sorttable)
			local depth = sorttable.depth
			for k, v in ipairs(sorttable) do
				if not IsValid(v) or not isstring(v:GetModel()) then continue end
				entnodes[v] = entnodes[parent]:AddNode(GetModelName(v))
				entnodes[v]:SetExpanded(true)

				entnodes[v].DoClick = function()
					net.Start("rgmSelectEntity")
						net.WriteEntity(v)
						net.WriteBool(false)
					net.SendToServer()
				end

				entnodes[v].Label.OnCursorEntered = function()
					HoveredEnt = v
				end

				entnodes[v].Label.OnCursorExited = function()
					HoveredEnt = nil
				end

				XSize = entnodes[v].Label:GetTextSize()
				local currentwidth = XSize + (depth * 17)

				if currentwidth > width then
					width = currentwidth
				end

				MakeChildrenList(v, sorttable[v])
			end
		end

		MakeChildrenList(parent, sortchildren)
	end

	entpanel:UpdateWidth(width + 8 + 32 + 16)
end

local function RGMBuildConstrainedEnts(parent, children, entpanel)
	entpanel:Clear()
	if not IsValid(parent) then return end

	conentnodes = {}

	conentnodes[parent] = entpanel:AddNode(GetModelName(parent))
	conentnodes[parent]:SetIcon("icon16/brick.png")
	conentnodes[parent]:SetExpanded(true)

	conentnodes[parent].Label.OnCursorEntered = function()
		HoveredEnt = parent
	end

	conentnodes[parent].Label.OnCursorExited = function()
		HoveredEnt = nil
	end

	for _, ent in ipairs(children) do
		conentnodes[ent] = conentnodes[parent]:AddNode(GetModelName(ent))
		conentnodes[ent]:SetIcon("icon16/brick_link.png")
		conentnodes[ent].Locked = false

		conentnodes[ent].DoClick = function()
			if conentnodes[ent].Locked then
				net.Start("rgmUnlockConstrained")
					net.WriteEntity(ent)
				net.SendToServer()
			else
				if parent:GetClass() ~= "prop_ragdoll" and not IsPropRagdoll then
					net.Start("rgmLockConstrained")
						net.WriteEntity(parent)
						net.WriteEntity(ent)
						net.WriteBool(false)
					net.SendToServer()
				else

					if LockMode == 1 then
						nodes[LockTo.ent][LockTo.id]:SetIcon(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].Icon)
						nodes[LockTo.ent][LockTo.id].Label:SetToolTip(BoneTypeSort[nodes[LockTo.ent][LockTo.id].Type].ToolTip)
					elseif LockMode == 2 then
						conentnodes[LockTo.id]:SetIcon("icon16/brick_link.png")
						conentnodes[LockTo.id].Label:SetToolTip(false)
					end

					LockMode = 2
					LockTo = { id = ent, ent = ent }

					surface.PlaySound("buttons/button9.wav")
					conentnodes[ent]:SetIcon("icon16/brick_edit.png")
					conentnodes[ent].Label:SetToolTip("#tool.ragdollmover.entlock")
				end
			end
		end

		conentnodes[ent].DoRightClick = function()
			local entmenu = DermaMenu(false, entpanel)

			local option = entmenu:AddOption("#tool.ragdollmover.entselect", function()
				if not IsValid(ent) then return end
				net.Start("rgmSelectEntity")
					net.WriteEntity(ent)
					net.WriteBool(true)
				net.SendToServer()
			end)

			local x = entpanel:LocalToScreen(5, 0)
			entmenu:Open()
		end

		conentnodes[ent].Label.OnCursorEntered = function()
			HoveredEnt = ent
		end

		conentnodes[ent].Label.OnCursorExited = function()
			HoveredEnt = nil
		end
	end
end

local function RGMMakeBoneButtonPanel(cat, cpanel)
	local parentpanel = vgui.Create("Panel", cat)
	parentpanel:SetSize(100, 30)
	cat:AddItem(parentpanel)

	parentpanel.ShowAll = vgui.Create("DButton", parentpanel)
	parentpanel.ShowAll:Dock(FILL)
	parentpanel.ShowAll:SetZPos(0)
	parentpanel.ShowAll:SetText("#tool.ragdollmover.listshowall")
	parentpanel.ShowAll.DoClick = function()
		local ent = pl.rgm.Entity
		if not IsValid(ent) or not IsValid(BonePanel) then return end
		RGMBuildBoneMenu(TreeEntities, ent, BonePanel)
	end

	parentpanel.ShowPhys = vgui.Create("DButton", parentpanel)
	parentpanel.ShowPhys:Dock(LEFT)
	parentpanel.ShowPhys:SetZPos(1)
	parentpanel.ShowPhys:SetText("#tool.ragdollmover.listshowphys")
	parentpanel.ShowPhys.DoClick = function()
		local ent = pl.rgm.Entity
		if not IsValid(ent) or not IsValid(BonePanel) then return end
		ShowOnlyPhysNodes(ent, BonePanel)
	end

	parentpanel.ShowNonphys = vgui.Create("DButton", parentpanel)
	parentpanel.ShowNonphys:Dock(RIGHT)
	parentpanel.ShowNonphys:SetZPos(1)
	parentpanel.ShowNonphys:SetText("#tool.ragdollmover.listshownonphys")
	parentpanel.ShowNonphys.DoClick = function()
		local ent = pl.rgm.Entity
		if not IsValid(ent) or not IsValid(BonePanel) then return end
		ShowOnlyNonPhysNodes(ent, BonePanel)
	end

	return parentpanel
end

local function rgmDoNotification(message)
	if RGM_NOTIFY[message] == true then
		notification.AddLegacy("#tool.ragdollmover.message" .. message, NOTIFY_ERROR, 5)
		surface.PlaySound("buttons/button10.wav")
	elseif RGM_NOTIFY[message] == false then
		notification.AddLegacy("#tool.ragdollmover.message" .. message, NOTIFY_GENERIC, 5)
		surface.PlaySound("buttons/button14.wav")
	end
end

function TOOL.BuildCPanel(CPanel)

	local Col1 = CCol(CPanel, "#tool.ragdollmover.gizmopanel")
		CCheckBox(Col1, "#tool.ragdollmover.localpos", "ragdollmover_localpos")
		CCheckBox(Col1, "#tool.ragdollmover.localang", "ragdollmover_localang")
		CNumSlider(Col1, "#tool.ragdollmover.scale", "ragdollmover_scale", 1.0, 50.0, 2)
		CNumSlider(Col1, "#tool.ragdollmover.width", "ragdollmover_width", 0.1, 1.0, 2)
		CCheckBox(Col1, "#tool.ragdollmover.fulldisc", "ragdollmover_fulldisc")

		local GizmoOffset = CCol(Col1, "#tool.ragdollmover.gizmooffsetpanel", true)
		CCheckBox(GizmoOffset, "#tool.ragdollmover.gizmolocaloffset", "ragdollmover_localoffset")
		CCheckBox(GizmoOffset, "#tool.ragdollmover.gizmorelativerotate", "ragdollmover_relativerotate")
		Gizmo1 = CGizmoSlider(GizmoOffset, "#tool.ragdollmover.xoffset", 1, -300, 300, 2)
		Gizmo2 = CGizmoSlider(GizmoOffset, "#tool.ragdollmover.yoffset", 2, -300, 300, 2)
		Gizmo3 = CGizmoSlider(GizmoOffset, "#tool.ragdollmover.zoffset", 3, -300, 300, 2)
		CButton(GizmoOffset, "#tool.ragdollmover.resetoffset", RGMResetGizmo)
		CButton(GizmoOffset, "#tool.ragdollmover.setoffset", RGMGizmoMode)

	local Col2 = CCol(CPanel, "#tool.ragdollmover.ikpanel")
		CCheckBox(Col2, "#tool.ragdollmover.ik3", "ragdollmover_ik_hand_L")
		CCheckBox(Col2, "#tool.ragdollmover.ik4", "ragdollmover_ik_hand_R")
		CCheckBox(Col2, "#tool.ragdollmover.ik1", "ragdollmover_ik_leg_L")
		CCheckBox(Col2, "#tool.ragdollmover.ik2", "ragdollmover_ik_leg_R")
		EnableIKButt = CButton(Col2, "#tool.ragdollmover.ikallon", RGMSelectAllIK)
		if GetConVar("ragdollmover_ik_leg_L"):GetBool() and GetConVar("ragdollmover_ik_leg_R"):GetBool() and GetConVar("ragdollmover_ik_hand_L"):GetBool() and GetConVar("ragdollmover_ik_hand_R"):GetBool() then
			EnableIKButt:SetText("#tool.ragdollmover.ikalloff")
		end
		CBAdditionalIKs(Col2, "#tool.ragdollmover.additional")

	local Col3 = CCol(CPanel, "#tool.ragdollmover.miscpanel")
		CCheckBox(Col3, "#tool.ragdollmover.lockselected", "ragdollmover_lockselected")
		local CB = CCheckBox(Col3, "#tool.ragdollmover.unfreeze", "ragdollmover_unfreeze")
		CB:SetToolTip("#tool.ragdollmover.unfreezetip")
		local DisFil = CCheckBox(Col3, "#tool.ragdollmover.disablefilter", "ragdollmover_disablefilter")
		DisFil:SetToolTip("#tool.ragdollmover.disablefiltertip")
		CCheckBox(Col3, "#tool.ragdollmover.drawskeleton", "ragdollmover_drawskeleton")
		CNumSlider(Col3, "#tool.ragdollmover.updaterate", "ragdollmover_updaterate", 0.01, 1.0, 2)

	CBinder(CPanel)

	Col4 = CCol(CPanel, "#tool.ragdollmover.bonemanpanel")

		local ColManip = CCol(Col4, "#tool.ragdollmover.bonemanip", true)
			-- Position
			Entry1 = CManipEntry(ColManip, 1)
			Pos1 = CManipSlider(ColManip, "#tool.ragdollmover.pos1", 1, 1, -300, 300, 2, Entry1) --x
			Pos2 = CManipSlider(ColManip, "#tool.ragdollmover.pos2", 1, 2, -300, 300, 2, Entry1) --y
			Pos3 = CManipSlider(ColManip, "#tool.ragdollmover.pos3", 1, 3, -300, 300, 2, Entry1) --z
			Entry1:SetVisible(false)
			Pos1:SetVisible(false)
			Pos2:SetVisible(false)
			Pos3:SetVisible(false)
			Entry1.Sliders = {Pos1, Pos2, Pos3}
			-- Angles
			Entry2 = CManipEntry(ColManip, 2)
			Rot1 = CManipSlider(ColManip, "#tool.ragdollmover.rot1", 2, 1, -180, 180, 2, Entry2) --pitch
			Rot2 = CManipSlider(ColManip, "#tool.ragdollmover.rot2", 2, 2, -180, 180, 2, Entry2) --yaw
			Rot3 = CManipSlider(ColManip, "#tool.ragdollmover.rot3", 2, 3, -180, 180, 2, Entry2) --roll
			Entry2:SetVisible(false)
			Rot1:SetVisible(false)
			Rot2:SetVisible(false)
			Rot3:SetVisible(false)
			Entry2.Sliders = {Rot1, Rot2, Rot3}
			--Scale
			Entry3 = CManipEntry(ColManip, 3)
			Scale1 = CManipSlider(ColManip, "#tool.ragdollmover.scale1", 3, 1, -100, 100, 2, Entry3) --x
			Scale2 = CManipSlider(ColManip, "#tool.ragdollmover.scale2", 3, 2, -100, 100, 2, Entry3) --y
			Scale3 = CManipSlider(ColManip, "#tool.ragdollmover.scale3", 3, 3, -100, 100, 2, Entry3) --z
			Entry3.Sliders = {Scale1, Scale2, Scale3}

			CButton(ColManip, "#tool.ragdollmover.resetallbones", RGMResetAllBones)

		CCheckBox(Col4, "#tool.ragdollmover.scalechildren", "ragdollmover_scalechildren")
		CCheckBox(Col4, "#tool.ragdollmover.smovechildren", "ragdollmover_smovechildren")
		local physmovecheck = CCheckBox(Col4, "#tool.ragdollmover.physmove", "ragdollmover_physmove")
		physmovecheck:SetToolTip("#tool.ragdollmover.physmovetip")

		CCheckBox(Col4, "#tool.ragdollmover.snapenable", "ragdollmover_snapenable")
		CNumSlider(Col4, "#tool.ragdollmover.snapamount", "ragdollmover_snapamount", 1, 180, 0)

		local ColBones = CCol(Col4, "#tool.ragdollmover.bonelist")
			RGMMakeBoneButtonPanel(ColBones, CPanel)
			BonePanel = vgui.Create("DTree", ColBones)
			BonePanel:SetTall(600)
			AddHBar(BonePanel)
			ColBones:AddItem(BonePanel)
			ColBones:AddItem(BonePanel.HBar)

	local ColEnts = CCol(CPanel, "#tool.ragdollmover.entchildren")

		EntPanel = vgui.Create("DTree", ColEnts)
		EntPanel:SetTall(150)
		AddHBar(EntPanel)
		EntPanel:SetShowIcons(false)
		ColEnts:AddItem(EntPanel)
		ColEnts:AddItem(EntPanel.HBar)
	
	local ColConsEnts = CCol(CPanel, "#tool.ragdollmover.conents")

		ConEntPanel = vgui.Create("DTree", ColConsEnts)
		ConEntPanel:SetTall(150)
		ColConsEnts:AddItem(ConEntPanel)
		local ConstrainedHelp = vgui.Create("DLabel", ColConsEnts)
		ConstrainedHelp:SetWrap(true)
		ConstrainedHelp:SetAutoStretchVertical(true)
		ConstrainedHelp:SetText("#tool.ragdollmover.conentshelp")
		ConstrainedHelp:SetDark(true)
		ColConsEnts:AddItem(ConstrainedHelp)

end

local function UpdateManipulationSliders(boneid, ent)
	if not IsValid(Pos1) then return end
	local pos, rot, scale = ent:GetManipulateBonePosition(boneid), ent:GetManipulateBoneAngles(boneid), ent:GetManipulateBoneScale(boneid)
	rot:Normalize()

	ManipSliderUpdating = true

	Pos1:SetValue(pos[1])
	Pos2:SetValue(pos[2])
	Pos3:SetValue(pos[3])
	Entry1:SetValue(math.Round(pos[1], 2) .. " " .. math.Round(pos[2], 2) .. " " .. math.Round(pos[3], 2))

	Rot1:SetValue(rot[1])
	Rot2:SetValue(rot[2])
	Rot3:SetValue(rot[3])
	Entry2:SetValue(math.Round(rot[1], 2) .. " " .. math.Round(rot[2], 2) .. " " .. math.Round(rot[3], 2))

	Scale1:SetValue(scale[1])
	Scale2:SetValue(scale[2])
	Scale3:SetValue(scale[3])
	Entry3:SetValue(math.Round(scale[1], 2) .. " " .. math.Round(scale[2], 2) .. " " .. math.Round(scale[3], 2))

	ManipSliderUpdating = false

end

net.Receive("rgmDeselectEntity", function(len)
	if IsValid(BonePanel) then BonePanel:Clear() end
	if IsValid(EntPanel) then EntPanel:Clear() end
	if IsValid(ConEntPanel) then ConEntPanel:Clear() end
	if pl.rgm and pl.rgm.Entity then
		pl.rgm.Entity = nil
		pl.rgm.Axis.EntAdvMerged = false
	end
	IsPropRagdoll = false
	TreeEntities = {}
	ScaleLocks = {}
end)

net.Receive("rgmUpdateSliders", function(len)
	UpdateManipulationSliders(pl.rgm.Bone, pl.rgm.Entity)
end)

net.Receive("rgmUpdateLists", function(len)
	IsPropRagdoll = net.ReadBool()
	ScaleLocks = {}

	local ents, children = {}, {}

	if IsPropRagdoll then
		for i = 1, net.ReadUInt(13) do
			local ent = net.ReadEntity()
			local data = {}
			data.id = net.ReadUInt(13)

			if net.ReadBool() then
				data.parent = net.ReadUInt(13)
			end

			ents[ent] = data

			children[ent] = {}
			ScaleLocks[ent] = {}

			for i = 1, net.ReadUInt(13) do
				children[ent][i] = net.ReadEntity()
			end
		end
	end

	local selectedent = net.ReadEntity()
	if not ents[selectedent] then
		ents[selectedent] = {id = -1}
	end

	TreeEntities = ents

	local physchildren = {}
	children[selectedent] = {}
	ScaleLocks[selectedent] = {}

	for i = 1, net.ReadUInt(13) do
		children[selectedent][i] = net.ReadEntity()
	end

	for i = 1, net.ReadUInt(13) do
		physchildren[i] = net.ReadEntity()
	end

	if IsValid(BonePanel) then
		RGMBuildBoneMenu(ents, selectedent, BonePanel)
	end
	if IsValid(EntPanel) then
		RGMBuildEntMenu(ents, children, EntPanel)
	end
	if IsValid(ConEntPanel) then
		RGMBuildConstrainedEnts(selectedent, physchildren, ConEntPanel)
	end
end)

net.Receive("rgmUpdateGizmo", function(len)
	local vector = net.ReadVector()
	if not IsValid(Gizmo1) then return end
	Gizmo1:SetValue(vector.x)
	Gizmo2:SetValue(vector.y)
	Gizmo3:SetValue(vector.z)
end)

net.Receive("rgmUpdateEntInfo", function(len)
	local ent = net.ReadEntity()
	local physchildren = {}
	ScaleLocks = {}
	ScaleLocks[ent] = {}

	local ents = {}

	IsPropRagdoll =  false
	if TreeEntities[ent] then
		IsPropRagdoll = true
		ents = TreeEntities
	else
		ents[ent] = { id = -1 }
	end

	for i = 1, net.ReadUInt(13) do
		physchildren[i] = net.ReadEntity()
	end

	if IsValid(BonePanel) then
		RGMBuildBoneMenu(ents, ent, BonePanel)
	end
	if IsValid(ConEntPanel) then
		RGMBuildConstrainedEnts(ent, physchildren, ConEntPanel)
	end
end)

net.Receive("rgmAskForPhysbonesResponse", function(len)
	local entcount = net.ReadUInt(13)
	for j = 1, entcount do
		local ent = net.ReadEntity()

		local count = net.ReadUInt(8)
		for i = 0, count do
			local bone = net.ReadUInt(8)
			local poslock = net.ReadBool()
			local anglock = net.ReadBool()
			local bonelock = net.ReadBool()

			if bone then
				nodes[ent][bone].Type = BONE_PHYSICAL
				nodes[ent][bone].poslock = poslock
				nodes[ent][bone].anglock = anglock
				nodes[ent][bone].bonelock = bonelock

				if LockMode == 1 and bone == LockTo.id and ent == LockTo.ent then
					nodes[ent][bone]:SetIcon("icon16/brick_add.png")
					nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.bonetolock")
				elseif bonelock then
					nodes[ent][bone]:SetIcon("icon16/lock_go.png")
					nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.lockedbonetobone")
				elseif anglock or poslock then
					nodes[ent][bone]:SetIcon("icon16/lock.png")
					nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.lockedbone")
				elseif ScaleLocks[ent][bone] then
					nodes[ent][bone]:SetIcon("icon16/lightbulb.png")
					nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.lockedscale")
				else
					nodes[ent][bone]:SetIcon("icon16/brick.png")
					nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.physbone")
				end
			end
		end
	end
end)

net.Receive("rgmAskForParentedResponse", function(len)
	local entcount = net.ReadUInt(13)

	for i = 1, entcount do
		local ent = net.ReadEntity()
		local count = net.ReadUInt(10)

		for i = 1, count do
			local bone = net.ReadUInt(10)

			if nodes[ent][bone] then
				nodes[ent][bone].Type = BONE_PARENTED
				nodes[ent][bone]:SetIcon("icon16/stop.png")
				nodes[ent][bone].Label:SetToolTip("#tool.ragdollmover.parentedbone")
			end
		end
	end
end)

net.Receive("rgmLockBoneResponse", function(len)
	local ent = net.ReadEntity()
	local boneid = net.ReadUInt(10)
	local poslock = net.ReadBool()
	local anglock = net.ReadBool()
	local scllock = net.ReadBool()

	nodes[ent][boneid].poslock = poslock
	nodes[ent][boneid].anglock = anglock
	nodes[ent][boneid].scllock = scllock
	ScaleLocks[ent][boneid] = scllock

	if poslock or anglock then
		nodes[ent][boneid]:SetIcon("icon16/lock.png")
		nodes[ent][boneid].Label:SetToolTip("#tool.ragdollmover.lockedbone")
	elseif scllock then
		nodes[ent][boneid]:SetIcon("icon16/lightbulb.png")
		nodes[ent][boneid].Label:SetToolTip("#tool.ragdollmover.lockedscale")
	else
		nodes[ent][boneid]:SetIcon(BoneTypeSort[nodes[ent][boneid].Type].Icon)
		nodes[ent][boneid].Label:SetToolTip(BoneTypeSort[nodes[ent][boneid].Type].ToolTip)
	end
end)

net.Receive("rgmLockToBoneResponse", function(len)
	local ent = net.ReadEntity()
	local lockbone = net.ReadUInt(10)

	if nodes[ent][lockbone] then
		nodes[ent][lockbone].bonelock = true
		nodes[ent][lockbone].poslock = false
		nodes[ent][lockbone].anglock = false
		nodes[ent][lockbone]:SetIcon("icon16/lock_go.png")
		nodes[ent][lockbone].Label:SetToolTip("#tool.ragdollmover.lockedbonetobone")

		rgmDoNotification(BONELOCK_SUCCESS)
	end
end)

net.Receive("rgmUnlockToBoneResponse", function(len)
	local ent = net.ReadEntity()
	local unlockbone = net.ReadUInt(10)

	if nodes[ent][unlockbone] then
		nodes[ent][unlockbone].bonelock = false
		nodes[ent][unlockbone]:SetIcon("icon16/brick.png")
		nodes[ent][unlockbone].Label:SetToolTip("#tool.ragdollmover.physbone")
	end
end)

net.Receive("rgmLockConstrainedResponse", function(len)
	local lock = net.ReadBool()
	local lockent = net.ReadEntity()

	if conentnodes[lockent] then
		conentnodes[lockent].Locked = lock
		if lock then
			conentnodes[lockent]:SetIcon("icon16/lock.png")
			rgmDoNotification(ENTLOCK_SUCCESS)
		else
			conentnodes[lockent]:SetIcon("icon16/brick_link.png")
		end
	end
end)

net.Receive("rgmSelectBoneResponse", function(len)
	local function SetVisiblePhysControls(bool)
		local inverted = not bool

		Pos1:SetVisible(inverted)
		Pos2:SetVisible(inverted)
		Pos3:SetVisible(inverted)
		Entry1:SetVisible(inverted)
		Rot1:SetVisible(inverted)
		Rot2:SetVisible(inverted)
		Rot3:SetVisible(inverted)
		Entry2:SetVisible(inverted)
	end

	local isphys = net.ReadBool()
	local ent = net.ReadEntity()
	local boneid = net.ReadUInt(10)

	if IsValid(ent) and boneid then
		UpdateManipulationSliders(boneid, ent)
	end

	if nodes then
		if isphys and nodes[ent] and nodes[ent][boneid] then
			SetVisiblePhysControls(true)
		else
			SetVisiblePhysControls(false)
		end
	end

	if IsValid(BonePanel) and nodes and nodes[ent] then
		BonePanel:SetSelectedItem(nodes[ent][boneid])

		Col4:InvalidateLayout()
	end

	rgmSendBonePos(pl, ent, boneid)
end)

net.Receive("rgmAskForNodeUpdatePhysicsResponse", function(len)
	local isphys = net.ReadBool()
	local entcount = net.ReadUInt(13)
	local physids, ents = {}

	for i = 1, entcount do
		local ent = net.ReadEntity()
		physids[ent] = {}

		local count = net.ReadUInt(8)
		if count ~= 0 then
			for i = 0, count - 1 do
				local id = net.ReadUInt(8)
				physids[ent][id] = true
			end
		end
	end


	if not IsValid(BonePanel) then return end
	UpdateBoneNodes(BonePanel, physids, isphys)
end)

net.Receive("rgmRequestBonePos", function(len)
	if not pl.rgm then return end
	rgmSendBonePos(pl, pl.rgm.Entity, pl.rgm.Bone)
end)

net.Receive("rgmNotification", function(len)
	local message = net.ReadUInt(5)

	rgmDoNotification(message)
end)

local material = CreateMaterial("rgmGizmoMaterial", "UnlitGeneric", {
	["$basetexture"] = 	"color/white",
  	["$model"] = 		1,
 	["$alphatest"] = 	1,
 	["$vertexalpha"] = 	1,
 	["$vertexcolor"] = 	1,
 	["$ignorez"] = 		1,
	["$nocull"] = 		1,
})

local VECTOR_FRONT = Vector(1, 0, 0)

function TOOL:DrawHUD()

	if not pl.rgm then pl.rgm = {} end

	local ent = pl.rgm.Entity
	local bone = pl.rgm.Bone
	local axis = pl.rgm.Axis
	local moving = pl.rgm.Moving or false
	--We don't draw the axis if we don't have the axis entity or the target entity,
	--or if we're not allowed to draw it.
	if IsValid(ent) and IsValid(axis) and bone then
		local scale = GizmoScale or 10
		local width = GizmoWidth or 0.5
		local moveaxis = axis[RGMGIZMOS.GizmoTable[pl.rgm.MoveAxis]]
		if moving and moveaxis then
			cam.Start({type = "3D"})
			render.SetMaterial(material)

			moveaxis:DrawLines(true, scale, width)

			cam.End()
			if moveaxis.IsDisc then
				local intersect = moveaxis:GetGrabPos(rgm.EyePosAng(pl))
				local fwd = (intersect - axis:GetPos())
				fwd:Normalize()
				axis:DrawDirectionLine(fwd, scale, false)
				local dirnorm = pl.rgm.DirNorm or VECTOR_FRONT
				axis:DrawDirectionLine(dirnorm, scale, true)
				axis:DrawAngleText(moveaxis, intersect, pl.rgm.StartAngle)
			end
		else
			cam.Start({type = "3D"})
			render.SetMaterial(material)

			axis:DrawLines(scale, width)
			cam.End()
		end
	end

	local tr = pl:GetEyeTrace()
	local aimedbone = IsValid(tr.Entity) and (tr.Entity:GetClass() == "prop_ragdoll" and pl.rgm.AimedBone or 0) or 0
	if IsValid(ent) and EntityFilter(ent, self) and SkeletonDraw then
		rgm.DrawSkeleton(ent)
	end

	if IsValid(HoveredEntBone) and EntityFilter(HoveredEntBone, self) and HoveredBone then
		rgm.DrawBoneConnections(HoveredEntBone, HoveredBone)
		rgm.DrawBoneName(HoveredEntBone, HoveredBone)
	elseif IsValid(HoveredEnt) and EntityFilter(HoveredEnt, self) then
		rgm.DrawEntName(HoveredEnt)
	elseif IsValid(tr.Entity) and EntityFilter(tr.Entity, self) and (not bone or aimedbone ~= bone or tr.Entity ~= pl.rgm.Entity) and not moving then
		rgm.DrawBoneConnections(tr.Entity, aimedbone)
		rgm.DrawBoneName(tr.Entity, aimedbone)
	end

end

end
