
ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.PrintName = "Ragdoll Mover Ghost"

ENT.Purpose = "Allow Ragdoll Mover to select gizmos in a func_brush"
ENT.Spawnable = false
ENT.Editable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:Initialize()
	-- To give the impression that there is no ghost entity, we disable properties,
	-- set the rendergroup to RENDERGROUP_OPAQUE, and we do not draw the model in ENT:Draw().

	self:SetModel("models/hunter/plates/plate1x1.mdl")
	self:DrawShadow(false)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_WORLD)

end

function ENT:CanTool(_, _, mode, _, _)
    return mode == "ragdollmover"
end

function ENT:CanProperty()
    return false
end

function ENT:Think()
	if ( CLIENT ) then
		local physobj = self:GetPhysicsObject()

		if ( IsValid( physobj ) ) then
			physobj:SetPos( self:GetPos() )
			physobj:SetAngles( self:GetAngles() )
		end
	end
end