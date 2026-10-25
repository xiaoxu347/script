-- 客户端自动找人 v3.18：侧闪转向优先使用已接收位置快照；保留短时保防、手动朝向与命中三段。
-- 执行整份文件。总开关默认关闭；F6 开始，F7 普攻，F8 防御，F9 全停；F10 自动反击默认开，需开启防御。
-- 重复运行会先清理旧实例。停止、切出、聊天、菜单、重生时恢复镜头和移动控制。
-- 默认「方式：直进」在普攻前摇中直线侧闪接近；另可切换正面 / 侧闪绕后模式。
-- 「起跳抢断」默认开，需 F8 / F10 反击开；测试默认收尾模式，关闭旧下砸避让。
-- 自动攻击只到第三段；确认上一拳命中才续拳，等原连段重置后再开新一轮。
-- 「间隙抢断」默认开，需 F8 / F6；直进最多 14 格起手，到近身距离刹停，命中后续到三段。

-- FINDER_CORE_BEGIN
local Core = {}
function Core.choose(records, currentId, maxRange, visibleOnly)
    local best, current
    for _, item in ipairs(records) do
        if item.distance <= maxRange and (not visibleOnly or item.visible) then
            if not best or item.distance < best.distance
                or (item.distance == best.distance and item.id < best.id) then best = item end
            if item.id == currentId then current = item end
        end
    end
    -- 只有新目标近至少 20% 才切换，避免距离相近的敌人导致镜头左右摇摆。
    if current and best and best.id ~= current.id and best.distance >= current.distance * 0.8 then
        return current
    end
    return best
end
function Core.alpha(response, deltaTime)
    return 1 - math.exp(-response * math.clamp(deltaTime, 0, 0.1))
end
function Core.moveAmount(distance, stopDistance, blocked, manual)
    return (distance > stopDistance and not blocked and not manual) and 1 or 0
end
function Core.number(text, old, minimum, maximum)
    local value = tonumber(text)
    if not value or value ~= value or math.abs(value) == math.huge then return old end
    return math.clamp(value, minimum, maximum)
end
function Core.attackReason(s)
    if not s.enabled then return "关闭" end
    if not s.ready then return "模块未就绪" end
    if s.manual then return "手动操作优先" end
    if s.selfBlocked then return "自身状态限制" end
    if not s.targetAlive or s.targetProtected then return "目标倒地或不可攻击" end
    if s.distance > s.range or s.height > 4 then return "等待进入攻击距离" end
    if not s.visible then return "目标被墙体遮挡" end
    if s.facing < 0.85 then return "正在转身对准" end
    if s.cooldown then return "等待出拳 / 收招冷却" end
    return nil
end
function Core.nextCombo(now, previous, previousTime, forced, airborne)
    local value = type(forced) == "string" and tonumber(forced:sub(1, 1)) or nil
    if value and value >= 1 and value <= 6 and value % 1 == 0 then return value, true end
    local combo = 1
    if type(previous) == "number" and previous >= 1 and previous < 4 and previous % 1 == 0
        and type(previousTime) == "number" and now >= previousTime and now - previousTime < 1.35 then
        combo = previous + 1
    end
    if combo == 4 and airborne then combo = 6 end
    return combo, false
end
-- FINDER_CORE_END

-- FINDER_FACING_BEGIN
local Facing = {}
function Facing.release(saved)
    if saved and saved.human.Parent and saved.human.AutoRotate == false then
        saved.human.AutoRotate = saved.autoRotate
    end
    return nil
end
function Facing.update(saved, character, human, root, enemyRoot, state, range)
    -- 手动移动、普攻和举防不取消朝向；游戏的禁止转向/倒地等状态仍优先。
    if not state or not enemyRoot or human.Sit or human.PlatformStand or root.Anchored
        or character:GetAttribute("Ragdolled") or state.CheckState("NoRotate")
        or state.CheckState("Freeze") or state.CheckState("Ragdoll") or state.CheckState("Rolling")
        or root:FindFirstChild("RollVelocity") then return Facing.release(saved) end
    local difference = enemyRoot.Position - root.Position
    local flat = Vector3.new(difference.X, 0, difference.Z)
    if difference.Magnitude > range or flat.Magnitude <= 0.05 then return Facing.release(saved) end
    if saved and saved.human ~= human then saved = Facing.release(saved) end
    saved = saved or {human=human, autoRotate=human.AutoRotate}
    human.AutoRotate = false
    root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
    return saved
end
-- FINDER_FACING_END

-- FINDER_DASH_GUARD_BEGIN
local DashGuard = {}
function DashGuard.side(id)
    if type(id)~="string" then return nil end
    return ({["99926906276382"]=1,["117658838411807"]=-1})[id:match("%d+")]
end
function DashGuard.observe(watch,id,now,position,speed,seeded)
    local side=DashGuard.side(id)
    if not side or speed<=0 or position<0 or position/speed>=.40 then return nil end
    local record={side=side,seenAt=now,startedAt=now-position/speed,seeded=seeded or false}
    watch.dash=record -- 侧闪可与 M1 同时发生，保留 latest/tracks/skill/unknown。
    return record
end
function DashGuard.active(record,now)
    return record and now>=record.startedAt and now-record.startedAt<.40
end
function DashGuard.threat(record,s)
    return DashGuard.active(record,s.now) and s.supported and not s.disabled and not s.unblockable
        and s.visible and s.distance<=s.range and math.abs(s.height)<=5
end
function DashGuard.select(entries)
    local best
    for _,entry in ipairs(entries) do
        if entry.dashDanger and (not best or entry.distance<best.distance) then best=entry end
    end
    if best then
        for _,entry in ipairs(entries) do
            if entry.player~=best.player and entry.attackScore then return nil end
        end
    end
    return best
end
function DashGuard.velocity(record,now,motion,physical)
    if not DashGuard.active(record,now) then return 0,0,"expired" end
    if motion and motion.at>record.seenAt and now-motion.at>=0 and now-motion.at<=.08
        and motion.x*motion.x+motion.z*motion.z<=260*260 then
        record.measured=true
        if motion.x*motion.x+motion.z*motion.z>=9 or now-record.seenAt>.06 then
            return motion.x,motion.z,"sample"
        end
    end
    if physical and physical.x*physical.x+physical.z*physical.z>=100
        and physical.x*physical.x+physical.z*physical.z<=260*260 then return physical.x,physical.z,"physics" end
    if not record.seeded and not record.measured and now-record.seenAt<=.06 and record.startX and record.startZ then
        return record.startX,record.startZ,"animation"
    end
    return 0,0,"none"
end
function DashGuard.aim(x,z,vx,vz)
    local distance=math.sqrt(x*x+z*z)
    if distance<=.05 then return x,z,0 end
    local ux,uz=x/distance,z/distance
    local radial=vx*ux+vz*uz
    -- 只预判横向 60ms，最多偏约 35°/6 格；仍覆盖当前看到的正面位置。
    local sx,sz=(vx-ux*radial)*.06,(vz-uz*radial)*.06
    local length=math.sqrt(sx*sx+sz*sz)
    local limit=math.min(6,distance*.70)
    if length>limit then sx,sz=sx*limit/length,sz*limit/length; length=limit end
    return x+sx,z+sz,length
end
-- FINDER_DASH_GUARD_END

-- FINDER_REPLICATED_AIM_BEGIN
local ReplicatedAim={}
function ReplicatedAim.read(api,player,character,root,ownRoot,range)
    if not api then return nil,"unavailable" end
    local ok,position,info=pcall(function()
        local entity=api.Holder.GetEntityFromPlayer(player)
        if not entity or entity.model~=character or entity.destroyed or entity.paused or entity.isContextOwner
            or entity.mountParentId or entity._renderOverride then return nil,"identity-or-state" end
        local latestTime,renderTime=entity.latestTime,api.Entity.GetTargetRenderTime(entity)
        local cf=api.Entity.GetCFrame(entity)
        if typeof(cf)~="CFrame" or type(latestTime)~="number" or type(renderTime)~="number"
            or latestTime~=latestTime or renderTime~=renderTime or renderTime<0 then return nil,"clock-or-type" end
        local ahead=latestTime-renderTime
        if ahead~=ahead or ahead<-.05 or ahead>.35 then return nil,"stale-or-future" end
        local p=cf.Position
        for _,v in ipairs({p.X,p.Y,p.Z}) do
            if v~=v or math.abs(v)==math.huge then return nil,"invalid-position" end
        end
        local delta=p-root.Position
        if delta.Magnitude>20 or math.abs(delta.Y)>8 or (p-ownRoot.Position).Magnitude>math.min(32,range+12) then
            return nil,"position-gap"
        end
        return p,{source="snapshot",ahead=ahead,gap=delta.Magnitude,position={p.X,p.Y,p.Z}}
    end)
    if not ok then return nil,"read-error" end
    return position,info
end
-- FINDER_REPLICATED_AIM_END

-- FINDER_ATTACK_DRIVER_BEGIN
-- 只调用游戏已加载的 M1 模块。它负责动画、原有命中检测和自身冷却。
local AttackDriver = {}
AttackDriver.__index = AttackDriver
function AttackDriver.new()
    return setmetatable({ held = nil, nextAt = 0, count = 0 }, AttackDriver)
end
function AttackDriver:release()
    local remote = self.held
    self.held = nil
    if remote then
        return pcall(function() remote:FireServer({ Request = "M1Up" }, nil, nil, nil) end)
    end
    return true
end
function AttackDriver:handoff()
    -- 用户真实按下左键时，原 Controls 接管按住状态并负责后续松开。
    self.held = nil
end
function AttackDriver:attack(adapter, character, combo, now)
    if adapter.maxCombo and (combo<1 or combo>adapter.maxCombo) then return false end
    if adapter.canChain and not adapter.canChain(combo,now,self.targetCharacter) then return false end
    if now < self.nextAt or adapter.state.CheckState("NoM1") then return false end
    local timing = adapter.moves[combo]
    assert(type(timing) == "table" and type(timing.AnimationLength) == "number", "角色 M1 时间表不兼容")
    if self.held ~= adapter.remote then
        self:release()
        self.held = adapter.remote -- 即使发送失败，停止路径也会尝试发送松开。
        adapter.remote:FireServer({ Request = "M1Down" }, nil, nil, nil)
    end
    character:SetAttribute("Combo", combo)
    character:SetAttribute("ComboTime", now)
    self.nextAt = now + math.max(0.1, timing.AnimationLength)
    self.lastShot=adapter.beforeAttack and adapter.beforeAttack(character,combo,now,timing,self.targetCharacter) or nil
    local ok, reason = pcall(adapter.moves.M1, character, combo, adapter.remote)
    if not ok then if self.lastShot then self.lastShot.cancelled=true end; self:release(); error(reason) end
    if not adapter.state.CheckState("NoM1") then
        if self.lastShot then self.lastShot.cancelled=true end
        self:release()
        error("M1 未进入游戏冷却状态，请检查客户端模块是否共享运行状态")
    end
    self.count += 1
    return true
end
-- FINDER_ATTACK_DRIVER_END

-- FINDER_DEFENSE_BEGIN
local Defense = { animations = {} }
-- 白名单来自用户导出的七个 M1 模块；包括 VirusOverlord 的两组变体。
-- 只识别真实攻击动画 ID，不把走路、受击或任意 Action 优先级动画当作攻击。
local function defenseSet(ids, hits, lengths)
    for combo, id in ipairs(ids) do
        local hit = hits[combo]
        Defense.animations[id] = { combo = combo, first = type(hit) == "table" and hit[1] or hit,
            last = type(hit) == "table" and hit[#hit] or hit, blockable = combo ~= 6,
            hits=type(hit)=="table" and #hit or 1, blockedLength=lengths and lengths[combo],
            nextHit=hits[combo+1] and (type(hits[combo+1])=="table" and hits[combo+1][1] or hits[combo+1])}
    end
end
defenseSet({"76817763934239", "107158215205776", "118155910784497", "94049292990999"}, {0.15, 0.195, 0.195, 0.254}, {.465,.5055555472333334,.4755555472333334})
defenseSet({"102035249362545", "103110334928175", "114428825390587", "93594559299345"}, {0.2, 7/30, 0.25, 0.25}, {.43555554723333334,.5022222139000001,.5188888805666668})
defenseSet({"91402231925177", "135814926466342", "107888141853305", "132346853658730"}, {0.2, 0.21, {13/60, 5/12}, 0.21}, {.43555554723333334,.5125555472333334,.6505555472333333})
defenseSet({"102189338494640", "92011043886513", "124362540783320", "86537950896012"}, {11/60, 0.15, 13/60, 13/60}, {.4522222139,.4522222139,.5188888805666667})
defenseSet({"86379026880720", "108207351431828", "117112790830378", "81497604775504"}, {11/60, 0.15, 13/60, 0.2}, {.4522222139,.4522222139,.5188888805666667})
defenseSet({"89551481973581", "116229832807839", "138338550423132", "89067930996367", "102626095190719"}, {11/60, 0.15, 13/60, 13/60, 0.333}, {.4522222139,.4522222139,.5188888805666667})
defenseSet({"117471011465133", "105544418876668", "85163848994960", "124528974461016", "89229858014776"}, {11/60, 0.15, 13/60, 13/60, 0.333}, {.4522222139,.4522222139,.5188888805666667})
Defense.animations["127256692704203"] = {combo=3, first=13/60, last=13/60, blockable=true,
    hits=1,blockedLength=.5188888805666667,nextHit=13/60}
Defense.animations["98091490332443"] = {combo=5, first=0.333, last=0.333, blockable=true}
Defense.animations["124413190367324"] = {combo=6, first=0.287, last=0.287, blockable=false}
function Defense.profile(id)
    return type(id) == "string" and Defense.animations[id:match("%d+")] or nil
end
function Defense.threat(s)
    local p = s.profile
    if not p or not s.playing or s.age > 1.5 or s.speed <= 0 or s.time < 0
        or s.time > p.last + 0.10 or s.distance > s.range or not s.visible or s.disabled then return nil end
    -- 游戏命中箱向前 3.5 格，宽 8.25 / 深 9.5；额外留出角色自身半径。
    local height = p.combo == 5 and 8 or (p.combo == 6 and 12 or 6.5)
    if math.abs(s.x) > 5.75 or s.forward < -2.75 or s.forward > 10 or math.abs(s.y) > height then return nil end
    return math.max(0, (p.first - s.time) / s.speed)
end
function Defense.reason(s)
    if not s.enabled then return "自动防御已关闭" end
    if not s.ready then return "防御模块未就绪" end
    if s.manual then return "手动操作优先" end
    if s.blocked then return "自身状态暂不可格挡" end
    return nil
end
function Defense.targetDisabled(s,proximity)
    -- 举防的敌人仍能随时松防出拳，不能因此解除近身预防。
    return s.ragdolled or s.protected or (not proximity and s.blocking)
end
function Defense.preempt(s)
    -- 这是距离/朝向预防，不代表已经识别到一次攻击；可以在面板关闭。
    if not s.enabled or not s.supported or s.disabled or s.unblockable or not s.visible then return false end
    local horizon = math.clamp((s.latency or 0.15) + 0.12, 0.20, 0.50)
    local range = math.min(s.range, 10 + math.clamp(s.closing or 0, 0, 80) * horizon + (s.holding and 1 or 0))
    return s.distance <= range and math.abs(s.height) <= 5 and s.facing >= 0.45
end
function Defense.engage(guard, adapter, now, releaseAttack, faceThreat)
    releaseAttack()
    faceThreat() -- 格挡是朝向判定；必须先对准，不能先 FDown 再慢慢转身。
    return guard:hold(adapter, now)
end
local DefenseDriver = {}
DefenseDriver.__index = DefenseDriver
function DefenseDriver.new()
    return setmetatable({held=nil, count=0, confirmed=0, seenBlock=false, holdUntil=0, latency=0.15,releaseLatency=0.15}, DefenseDriver)
end
function DefenseDriver:release(now)
    local a = self.held
    self.held, self.holdUntil, self.seenBlock = nil, 0, false
    if not a then return true end
    self.releaseAt=now or os.clock()
    -- 三项清理独立尝试，不能因为一个错误留下按住状态。
    local ok1, err1 = pcall(a.state.SetBlockHeld, false)
    local ok2, err2 = pcall(function() a.remote:FireServer({Request="FUp"}, nil, nil, nil) end)
    if a.guardEvent then pcall(a.guardEvent, "FUp") end
    local ok3, err3 = pcall(a.stopBlockAnimation)
    return ok1 and ok2 and ok3, err1 or err2 or err3
end
function DefenseDriver:observeRelease(blocking,now)
    if self.releaseAt and not blocking and now>=self.releaseAt then
        local sample=math.clamp(now-self.releaseAt,.05,.40)
        self.releaseLatency=self.releaseLatency*.5+sample*.5
        self.releaseAt=nil
    end
end
function DefenseDriver:handoff()
    -- 真正按下 F 后由原 Controls 接管，不能再发送 FUp 抵消用户的 FDown。
    self.held, self.holdUntil, self.seenBlock = nil, 0, false
end
function DefenseDriver:hold(a, now)
    if self.held and self.held ~= a then self:release() end
    if not self.held then
        local n = a.uniqueId()
        self.held, self.seenBlock = a, false
        self.awaitClear = a.isBlocking and a.isBlocking() or false
        self.sentAt = now
        local ok, reason = pcall(function()
            a.state.SetBlockHeld(true)
            a.remote:FireServer({Request="FDown", N=n}, nil, nil, nil)
            if a.guardEvent then pcall(a.guardEvent, "FDown", n) end
        end)
        if not ok then self:release(); error(reason) end
        self.count += 1
    end
    self.holdUntil = now + 0.32
    return true
end
function DefenseDriver:observe(blocking, now)
    if self.held and self.awaitClear then
        if not blocking then self.awaitClear=false end
        return -- 旧 FUp 尚未回传时，不能把遗留的 Blocking=true 当作新 FDown 已生效。
    end
    if self.held and blocking and not self.seenBlock then
        self.confirmed += 1
        self.seenBlock = true
        if now and self.sentAt and now >= self.sentAt then
            local sample = math.clamp(now - self.sentAt, 0.06, 0.38)
            -- 延迟升高立即增加提前量，下降缓慢回落，避免一次快回执导致过晚举防。
            self.latency = math.max(sample, self.latency * 0.9 + sample * 0.1)
        end
    end
end
function DefenseDriver:expire(now)
    if self.held and now >= self.holdUntil then
        self:release()
    end
    return self.held ~= nil
end
-- FINDER_DEFENSE_END

-- FINDER_COUNTER_BEGIN
local Counter = {}
function Counter.interruptPriority(name)
    -- Core 的枚举数值不是优先级顺序；不能用 Value >= Action.Value 判断。
    return name=="Action" or name=="Action2" or name=="Action3" or name=="Action4"
end
function Counter.record(profile, now, time, seeded)
    return {profile=profile, seenAt=now, startedAt=now-time, lastTime=time,
        whiffValid=not seeded and time>=0 and time<profile.first-.04,
        gapValid=not seeded and time >= 0 and time < profile.last + 0.10,
        valid=not seeded and profile.combo >= 4 and time >= 0 and time < profile.last + 0.10}
end
function Counter.observe(record, now, time, speed, playing)
    if not record.valid and not record.gapValid then return end
    local changed = math.abs(speed - 1) > 0.02
    local blockSlow = record.profile.combo <= 3 and (math.abs(speed-.65)<.02 or math.abs(speed-.6)<.02)
    if now - record.seenAt > 1.8 or time < 0 or (playing and ((changed and not blockSlow)
        or time + 0.03 < record.lastTime)) then record.valid,record.gapValid = false,false; return end
    if playing and changed then record.valid = false end
    if not playing then
        -- 动画提前中断不算后摇。已实际观察到末次打击过去，才允许保留短暂窗口。
        if not record.finished then record.valid = false end
        if not record.blockedAt then record.gapValid = false end
        return
    end
    record.lastTime = time
    record.startedAt = math.min(record.startedAt, now - time)
    if time > record.profile.last + 0.10 then record.finished = true end
end
function Counter.window(record, now, latency, timing, needsRelease)
    if not record or not record.valid or not record.finished or not record.wasThreat or record.consumed then return false end
    if type(timing) ~= "table" or type(timing.AnimationLength) ~= "number" then return false end
    local hit = timing.HitTime
    if type(hit) == "table" then hit = hit[#hit] end
    if type(hit) ~= "number" then return false end
    local lag = math.clamp(latency, 0.06, 0.38)
    -- 七个导出 M1 模块都在第 4/5/6 段命中时加 1.25 秒 NoM1。
    -- 这是普攻冷却估计，不代表对方不能格挡、闪避或用技能。
    local deadline = record.startedAt + record.profile.last + 1.25 - lag - 0.06
    local recovery = math.max(timing.AnimationLength, timing.BlockedLength or 0, hit)
    local releaseWait = type(needsRelease) == "number" and math.clamp(needsRelease, 0, lag) or (needsRelease and lag or 0)
    local budget = recovery + lag + 0.08 + releaseWait
    return deadline - now >= budget, deadline, budget
end
function Counter.select(entries, now, latency, timing, needsRelease, preferred)
    local best
    for _, entry in ipairs(entries) do
        if (not preferred or entry.player == preferred) and entry.eligible and not entry.attack and not entry.unknown
            and Counter.window(entry.record, now, latency, timing, needsRelease) then
            local contested = false
            for _, other in ipairs(entries) do
                if other ~= entry and (other.attack or other.preempt or other.unknown) then contested = true; break end
            end
            if not contested and (not best or entry.distance < best.distance) then best = entry end
        end
    end
    return best
end
function Counter.strikeReason(s)
    if not s.valid then return "反击窗口已失效" end
    if s.manual then return "手动操作优先" end
    if s.blocking or s.blockHeld then return "等待松防确认" end
    if s.blocked then return "自身状态限制" end
    if s.cooldown then return "等待自身出拳冷却" end
    if s.facing < 0.85 then return "等待对准反击目标" end
    return nil
end
function Counter.begin(entry, now, guard, driver)
    driver:release()
    local ok, err = guard:release()
    if not ok then error(err) end
    return {player=entry.player, record=entry.record, phase="release", releaseAt=now}
end
function Counter.commit(action, driver, adapter, character, combo, now, gates)
    if combo>3 then return false,"三段结束，等待原连段重置" end
    if action.phase ~= "release" or action.record.consumed then return false, "本次反击已处理" end
    local reason = Counter.strikeReason(gates)
    if reason then return false, reason end
    if not driver:attack(adapter, character, combo, now) then return false, "等待自身出拳冷却" end
    driver:release()
    action.record.consumed, action.phase = true, "struck"
    action.punches, action.lastCombo, action.startedAt = 1,combo,now
    action.shot=driver.lastShot
    local timing = adapter.moves[combo]
    action.recoverAt = now + math.max(timing.AnimationLength, timing.BlockedLength or 0)
    return true
end
function Counter.chainReason(action, s)
    if not s.enabled then return "单拳反击完成" end
    if (action.lastCombo or 3) >= 3 or (action.punches or 0) >= 3 then return "三段完成，恢复防御" end
    if s.now - action.startedAt > 2.8 then return "连击窗口结束" end
    if not s.eligible then return "目标脱离攻击范围或受保护" end
    if s.threat then return "出现新威胁，恢复防御" end
    if s.damaged then return "自身受击，恢复防御" end
    return nil
end
function Counter.chain(action, driver, adapter, character, combo, now, gates)
    if combo>3 then return false end
    if action.phase ~= "struck" then return false end
    if Counter.chainReason(action,{enabled=true,now=now,eligible=true}) then return false end
    if Counter.strikeReason(gates) then return false end
    local previousHitAt=action.shot and action.shot.confirmedAt
    if not driver:attack(adapter,character,combo,now) then return false end
    driver:release()
    action.punches += 1
    action.lastCombo = combo
    action.shot=driver.lastShot
    action.previousHitAt=previousHitAt
    action.recoverAt = now + math.max(adapter.moves[combo].AnimationLength,adapter.moves[combo].BlockedLength or 0)
    return true
end
-- FINDER_COUNTER_END

-- FINDER_GAP_BEGIN
local Gap = {}
function Gap.feedback(entries, at, now)
    if now-at > .12 or now<at then return nil end
    local chosen
    for _,entry in ipairs(entries) do
        local r=entry.record
        if entry.feedbackEligible and r and r.gapValid and r.profile.blockable and r.wasThreat
            and at>=r.seenAt and at-r.seenAt<.85 and not r.consumed then
            if chosen then return nil end -- SmallBlock 不带攻击者；多人同时打来时不猜。
            chosen=entry
        end
    end
    if not chosen then return nil end
    local r=chosen.record
    if r.blockedAt and at-r.blockedAt<.06 then return nil end
    r.blockedAt=at
    r.blockedHits=(r.blockedHits or 0)+1
    r.gapReady=r.blockedHits >= (r.profile.hits or 1)
    return chosen
end
function Gap.window(record,now,latency,timing)
    if not record or not record.gapValid or not record.gapReady or not record.blockedAt or record.consumed then return false end
    if not timing or type(timing.HitTime)~="number" and type(timing.HitTime)~="table" then return false end
    local hit=type(timing.HitTime)=="table" and timing.HitTime[1] or timing.HitTime
    local lag=math.clamp(latency*.5,.03,.19)
    local p=record.profile
    local interval=p.combo>=4 and 1.25 or (p.blockedLength and p.nextHit and p.blockedLength-p.last+p.nextHit)
    if not interval then return false end
    -- SmallBlock 是本机收到反馈的时刻；扣除估计回传时间，再预算出拳上行与前摇。
    local deadline=record.blockedAt+interval-lag-.025
    local budget=hit+lag+.02
    return deadline-now>=budget,deadline,budget
end
function Gap.select(entries,now,latency,timing,preferred)
    local best
    for _,entry in ipairs(entries) do
        if (not preferred or entry.player==preferred) and entry.eligible and not entry.unknown
            and not entry.otherAttack and Gap.window(entry.record,now,latency,timing) then
            local contested=false
            for _,other in ipairs(entries) do
                if other~=entry and (other.attack or other.preempt or other.unknown) then contested=true; break end
            end
            if not contested and (not best or entry.distance<best.distance) then best=entry end
        end
    end
    return best
end
-- FINDER_GAP_END

-- FINDER_CONTACT_BEGIN
local Contact={}
function Contact.shot(target,combo,now,timing,selected)
    local hit=timing.HitTime
    local first=type(hit)=="table" and hit[1] or hit
    local last=type(hit)=="table" and hit[#hit] or hit
    return {target=target,combo=combo,sentAt=now,earliest=now+math.max(0,(first or .15)-.07),
        deadline=now+math.max(timing.AnimationLength or .4,(last or .2)+.4),selected=selected}
end
function Contact.feedback(shot,payload,now,ambiguous)
    if not shot or not shot.target or type(payload)~="table" or shot.cancelled or shot.confirmedAt or ambiguous
        or now<shot.earliest or now>shot.deadline then return false end
    local code=tostring(payload.C)
    local combo=tonumber(code:match("^[123]$") or code:match("^([123])[12]$"))
    if payload.Request~="ME" or payload.V~=shot.target or combo~=shot.combo then return false end
    -- N 的含义没有完整服务器源码，不把它当成攻击者身份；另检查同时攻击该目标的玩家。
    shot.confirmedAt=now
    return true
end
function Contact.canContinue(shot,now)
    return shot and not shot.cancelled and shot.confirmedAt and now>=shot.confirmedAt
        and now-shot.confirmedAt<=.75 and shot.combo<3
end
function Contact.canStart(shot,combo,now,target)
    return combo==1 or (combo<=3 and Contact.canContinue(shot,now) and shot.combo+1==combo and shot.target==target)
end
function Contact.pending(shot,now)
    return shot and not shot.cancelled and now>=shot.sentAt and now<=shot.deadline
end
local hitReactions={ ["116197836876010"]=true,["137066705482028"]=true,
    ["129889605552498"]=true,["76419353507732"]=true }
function Contact.actionKind(shot,target,id,at,position,seeded,now)
    -- 受击动画在 AnimationPlayed 回调中可能暂为 Action，随后才降为 Idle。
    -- 只关联已观测的受击动画和当前目标本拳 ME；不整体忽略未知技能。
    local key=type(id)=="string" and id:match("%d+")
    if not hitReactions[key] or seeded or position<0 or position>.08 or now<at
        or not Contact.pending(shot,at) or shot.target~=target or at<shot.earliest then return "unknown" end
    if shot.confirmedAt then
        return math.abs(shot.confirmedAt-at)<=.10 and "reaction" or "unknown"
    end
    return now-at<.10 and "pending" or "unknown"
end
function Contact.markUnknown(watch,at,id)
    -- 延后核对的旧动画不能覆盖随后已经识别的攻击或技能。
    if watch.actionAt and at<watch.actionAt then return false end
    if watch.dash and at<watch.dash.seenAt then return false end
    if watch.skill then watch.skill.ended=true end
    watch.dash=nil
    watch.latest,watch.jump,watch.unknownUntil,watch.actionAt,watch.unknownId=nil,nil,at+.65,at,id
    return true
end
function Contact.pressure(shot,previousHitAt,now)
    local hitAt=shot and (shot.confirmedAt or previousHitAt)
    return Contact.pending(shot,now) and hitAt and now>=hitAt and now-hitAt<=.50
end
function Contact.targetInterrupted(s)
    -- 命中后的短暂压制期内，对手排队/重新播放的普攻起始帧不结束整段连击。
    -- 新技能、其他攻击者、自己受击及本拳未命中仍由各自的门槛中止。
    return s.unknown or (not s.pressure and (s.changed or s.otherAttack or s.attack))
end
function Contact.chainReason(shot,now)
    if Contact.canContinue(shot,now) then return nil end
    if not shot or shot.cancelled or now>shot.deadline then return "未确认命中，停止续拳" end
    return "等待本拳命中反馈"
end
-- FINDER_CONTACT_END

-- FINDER_COMPAT_BEGIN
local Compat={gameId=5265857965}
function Compat.placeReason(placeId,gameId)
    if gameId~=Compat.gameId then
        return "当前不是已适配游戏：GameId="..tostring(gameId).."，PlaceId="..tostring(placeId)
    end
    return nil
end
function Compat.moduleReason(state,moves,ids)
    if type(state)~="table" or type(state.CheckState)~="function" or type(state.SetBlockHeld)~="function" then
        return "ClientState 攻防接口不兼容"
    end
    if type(ids)~="table" or type(ids.GetUniqueId)~="function" then return "UniqueIdGenerator 接口不兼容" end
    if type(moves)~="table" or type(moves.M1)~="function" then return "M1 接口不兼容" end
    local function valid(value,minimum)
        return type(value)=="number" and value==value and value<math.huge and value>=minimum
    end
    for combo=1,3 do
        local timing=moves[combo]
        if type(timing)~="table" or not valid(timing.AnimationLength,.001)
            or (timing.BlockedLength~=nil and not valid(timing.BlockedLength,0)) then
            return "第 "..tostring(combo).." 段 M1 冷却数据不兼容"
        end
        local hit=timing.HitTime
        if type(hit)=="table" then
            if #hit==0 then return "第 "..tostring(combo).." 段 M1 打击时点为空" end
            local previous=0
            for _,at in ipairs(hit) do
                if not valid(at,previous) then return "第 "..tostring(combo).." 段 M1 打击时点不兼容" end
                previous=at
            end
        elseif not valid(hit,0) then return "第 "..tostring(combo).." 段 M1 打击时点不兼容" end
    end
    return nil
end
-- FINDER_COMPAT_END

-- FINDER_SKILL_BEGIN
local Skill={profiles={
    body={name="身体闪烁",mode="guard",animation="126102858255615",duration=1.05,first=.40,last=.40,combo=0},
    fury={name="闪步狂怒",mode="guard",animation="81828368631848",duration=1.50,first=1.10,last=1.10,combo=0},
    lightning={name="闪电光芒",mode="interrupt",animation="102273007149848",duration=.80,first=.50,last=.55,combo=0},
    frontdash={name="前冲刺攻击",mode="guard",phase="approach",duration=29/120+.45+13/30+.10,
        first=29/120+.15,last=29/120+.45+.15,combo=0},
    frontdashHit={name="前冲刺攻击",mode="guard",phase="strike",duration=13/30+.10,first=.15,last=.15,combo=0}
}}
local frontDashAnimations={
    ["114458287091546"]={phase="frontdash"},["74625380701262"]={phase="frontdashHit"},
    ["118875360854379"]={phase="frontdash",selected=4},["77218077548995"]={phase="frontdashHit",selected=4},
    ["136822834992496"]={phase="frontdash",selected=4},["83033887169522"]={phase="frontdashHit",selected=4}
}
function Skill.profile(id,selected)
    if type(id)~="string" then return nil end
    local key=id:match("%d+")
    local dash=frontDashAnimations[key]
    if dash and type(selected)=="number" and selected>=1 and selected<=7 and selected%1==0
        and (not dash.selected or selected==dash.selected) then return Skill.profiles[dash.phase] end
    if selected~=3 then return nil end
    for _,p in pairs(Skill.profiles) do if p.animation and p.animation==key then return p end end
end
function Skill.event(request,selected)
    if selected~=3 then return nil end
    return ({BFS=Skill.profiles.body,FlashstepFurySound=Skill.profiles.fury,LightningFlashI=Skill.profiles.lightning})[request]
end
function Skill.observe(previous,profile,now,time,seeded,speed)
    if previous and previous.profile==profile and now-previous.seenAt<.25 then return previous end
    return {profile=profile,seenAt=now,startedAt=now-time/math.max(speed or 1,.01),
        fresh=not seeded and time>=0 and time<=.08,consumed=false}
end
function Skill.active(record,now)
    return record and not record.ended and now>=record.startedAt and now-record.startedAt<=record.profile.duration
end
function Skill.threat(record,s)
    return Skill.active(record,s.now) and s.visible and not s.ragdolled and s.distance<=32 and math.abs(s.height)<=10
end
function Skill.window(record,now,latency,timing,lastDamageAt)
    if not Skill.active(record,now) or record.profile.mode~="interrupt" or not record.fresh or record.consumed
        or (lastDamageAt or -math.huge)>=record.seenAt then return false end
    local hit=timing and timing.HitTime
    hit=type(hit)=="table" and hit[1] or hit
    if type(hit)~="number" then return false end
    local remaining=record.startedAt+record.profile.first-now
    local budget=hit+math.clamp((latency or .15)*.5,.03,.19)+.04
    return remaining>=budget,remaining,budget
end
function Skill.select(entries,now,latency,timing,lastDamageAt,preferred)
    local best
    for _,e in ipairs(entries) do
        if (not preferred or preferred==e.player) and e.eligible and not e.unknown and not e.otherAttack
            and Skill.window(e.skill,now,latency,timing,lastDamageAt) then
            local contested=false
            for _,other in ipairs(entries) do
                if other~=e and (other.attack or other.preempt or other.unknown) then contested=true;break end
            end
            if not contested and (not best or e.distance<best.distance) then best=e end
        end
    end
    return best
end
-- FINDER_SKILL_END

-- FINDER_WHIFF_BEGIN
local Whiff={}
function Whiff.crosses(a,b,height)
    local low,high=0,1
    for _,axis in ipairs({{"x",-6.25,6.25},{"forward",-3.25,10.5},{"y",-height,height}}) do
        local key,minimum,maximum=axis[1],axis[2],axis[3]
        local delta=b[key]-a[key]
        if math.abs(delta)<.0001 then
            if a[key]<minimum or a[key]>maximum then return false end
        else
            local t1,t2=(minimum-a[key])/delta,(maximum-a[key])/delta
            low=math.max(low,math.min(t1,t2)); high=math.min(high,math.max(t1,t2))
            if low>high then return false end
        end
    end
    return true
end
function Whiff.observe(r,s)
    if not r.whiffValid or r.whiffBad then return end
    local p=r.profile
    if s.damaged or r.blockedAt or s.now-r.seenAt>1.8 or math.abs(s.speed-1)>.02 then r.whiffBad=true; return end
    if not s.playing then if not r.whiffReady then r.whiffBad=true end; return end
    if r.whiffTime and s.time+.025<r.whiffTime then r.whiffBad=true; return end
    if not r.whiffReady and r.whiffAt and s.now-r.whiffAt>.09 then r.whiffBad=true; return end
    if s.time<p.first-.04 then r.whiffEarly=true end
    if s.time>=p.first-.04 and (not r.whiffTime or r.whiffTime<=p.last+.04) and not r.whiffReady then
        if not r.whiffEarly then r.whiffBad=true; return end
        local height=p.combo==5 and 8.5 or (p.combo==6 and 12.5 or 7)
        local inside=math.abs(s.x)<=6.25 and s.forward>=-3.25 and s.forward<=10.5 and math.abs(s.y)<=height
        if inside or (r.whiffPoint and Whiff.crosses(r.whiffPoint,s,height)) then r.whiffBad=true; return end
        if not r.whiffTime or s.time>r.whiffTime+.002 then r.whiffSamples=(r.whiffSamples or 0)+1 end
    end
    r.whiffAt,r.whiffTime,r.whiffPoint=s.now,s.time,{x=s.x,y=s.y,forward=s.forward}
    if s.time>p.last+.04 and r.whiffEarly and (r.whiffSamples or 0)>=2 then r.whiffReady=true end
end
function Whiff.window(r,now,latency,timing,lastDamageAt,travelTime)
    if not r or not r.whiffReady or r.whiffBad or r.blockedAt or r.consumed
        or (lastDamageAt or -math.huge)>=r.seenAt then return false end
    local hit=timing and timing.HitTime
    hit=type(hit)=="table" and hit[1] or hit
    if type(hit)~="number" then return false end
    local p=r.profile
    -- 七个导出角色的前 3 拳 BlockedLength 均比 AnimationLength 长 .105 秒。
    -- 终结段空挥存在 .81 秒 M1Whiff 限制，取较短硬直而非 1.25 秒普攻冷却。
    local endTime=p.combo>=4 and p.last+.81
        or (p.blockedLength and p.nextHit and p.blockedLength-.105+p.nextHit)
    if not endTime then return false end
    local lag=math.clamp(latency*.5,.03,.19)
    local deadline=r.startedAt+endTime-lag-.035
    local budget=hit+lag+.025+math.max(0,travelTime or 0)
    return deadline-now>=budget,deadline,budget
end
function Whiff.select(entries,now,latency,timing,lastDamageAt,preferred)
    local best
    for _,entry in ipairs(entries) do
        if not entry.whiffPlanFailed and (not preferred or entry.player==preferred) and (entry.eligible or entry.whiffReachable) and not entry.unknown and not entry.otherAttack
            and Whiff.window(entry.record,now,latency,timing,lastDamageAt,entry.whiffTravel) then
            local contested=false
            for _,other in ipairs(entries) do
                if other~=entry and (other.attack or other.preempt or other.unknown) then contested=true; break end
            end
            if not contested and (not best or entry.distance<best.distance) then best=entry end
        end
    end
    return best
end
function Whiff.plan(entry,now,latency,timing,lastDamageAt,committedRear)
    if entry.rearRoute and Whiff.window(entry.record,now,latency,timing,lastDamageAt,entry.rearTravel) then
        entry.whiffRoute,entry.whiffTravel,entry.whiffReachable=entry.rearRoute,entry.rearTravel,true
    elseif committedRear then
        entry.whiffPlanFailed=true -- 已选择绕后就不能中途改成迎面出拳。
    end
end
-- FINDER_WHIFF_END

-- FINDER_INTERRUPT_BEGIN
local Interrupt={}
function Interrupt.frontOnly(style)
    return style=="front"
end
function Interrupt.canFlank(style)
    return style==nil or style=="weave"
end
function Interrupt.advanceEligible(s)
    return s.visible and not s.disabled and math.abs(s.height)<=3
        and s.distance>s.range and s.distance<=s.limit
end
function Interrupt.advanceStop(range)
    return math.min(5.8,range-.65)
end
function Interrupt.observe(r,s)
    if r.interruptBad or r.profile.combo>3 then return end
    if not r.gapValid or s.damaged or s.now-r.seenAt>1.5
        or math.abs(s.speed-1)>.02 or not s.playing then r.interruptBad=true; return end
    if r.interruptTime and (s.time+.025<r.interruptTime or s.now-r.interruptAt>.09) then
        r.interruptBad=true; return
    end
    if s.time<r.profile.first-.025 then r.interruptEarly=true end
    r.interruptAt,r.interruptTime=s.now,s.time
    if r.interruptEarly and s.time>=r.profile.last+.035 then r.interruptReady=true end
end
function Interrupt.window(r,now,latency,timing,travel,lastDamageAt,style)
    local front=Interrupt.frontOnly(style)
    local advance=style=="advance"
    if not r or r.consumed or (r.profile.combo>3 and not advance)
        or (lastDamageAt or -math.huge)>=r.seenAt then return false end
    local hit=timing and timing.HitTime
    hit=type(hit)=="table" and hit[1] or hit
    if type(hit)~="number" then return false end
    if not front and (not travel or travel<0 or travel==math.huge or travel>hit-.035) then return false end
    local deadline,source,whiffBudget
    if r.gapValid and r.gapReady and r.blockedAt then
        local _,finish=Gap.window(r,now,latency,timing)
        deadline,source=finish,"block"
    elseif advance and r.whiffReady and not r.whiffBad then
        local _,finish,budget=Whiff.window(r,now,latency,timing,lastDamageAt,0)
        deadline,source,whiffBudget=finish,"whiff",budget
    elseif r.profile.combo<=3 and r.interruptReady and not r.interruptBad and r.profile.blockedLength and r.profile.nextHit then
        local lag=math.clamp(latency*.5,.03,.19)
        deadline=r.startedAt+r.profile.blockedLength-.105+r.profile.nextHit-lag-.025
        source="animation"
    end
    -- 侧闪与自己的前摇重叠：必须在本拳打击前、对手下一段预计打击前到背面。
    -- 这是位置/时序机会，不声称对方不能转向、提前用技能或脱离。
    -- 正面没有侧闪避开下一击，必须预算完整出拳前摇、上行时间及余量。
    local budget=(front or advance) and (whiffBudget or hit+math.clamp(latency*.5,.03,.19)+.02) or travel
    return deadline~=nil and deadline-now>=budget,deadline,source,budget
end
function Interrupt.select(entries,now,latency,timing,lastDamageAt,preferred,style)
    local front=Interrupt.frontOnly(style)
    local advance=style=="advance"
    local best
    for _,e in ipairs(entries) do
        local eligible=advance and e.interruptReachable or (not advance and e.eligible)
        local routeReady=front or (e.interruptRoute and (not advance or e.interruptRoute.kind=="advance"))
        if (not preferred or e.player==preferred) and eligible and routeReady and not e.unknown and not e.otherAttack then
            local fits,deadline,source=Interrupt.window(e.record,now,latency,timing,e.interruptTravel,lastDamageAt,style)
            if fits then
                local contested=false
                for _,other in ipairs(entries) do
                    if other~=e and (other.attack or other.preempt or other.unknown) then contested=true; break end
                end
                local score=front and e.distance or e.interruptTravel
                local bestScore=best and (front and best.distance or best.interruptTravel)
                if not contested and (not best or score<bestScore) then
                    best=e; e.interruptDeadline,e.interruptSource,e.interruptStyle=deadline,source,style or "weave"
                end
            end
        end
    end
    return best
end
function Interrupt.motion(s)
    if s.manual or s.damaged or s.blocked or s.otherThreat or s.unknown then return "abort" end
    local advance=s.style=="advance"
    local limit=advance and s.startRange or s.range+2
    if not s.alive or s.protected or not s.visible or s.distance>limit or math.abs(s.height)>4 then return "abort" end
    if s.now>s.deadline then return "abort" end
    if advance and (not s.forward or s.forward<=0 or not s.lateral or math.abs(s.lateral)>2.5) then return "abort" end
    if (advance and s.distance<=Interrupt.advanceStop(s.range))
        or (not advance and s.rear and s.distance<=s.range-.15) then return "arrive" end
    if not s.velocity or not s.path then return "abort" end
    return "move"
end
-- FINDER_INTERRUPT_END

-- FINDER_SLAM_BEGIN
local Slam={safeDistance=12.5}
function Slam.threat(s)
    local p=s.profile
    if not p or p.combo~=6 or p.blockable or not s.playing or s.speed<=0 or s.time<0
        or s.time>p.last+.12 or s.age>1.5 or s.disabled or not s.visible or s.distance>18 then return nil end
    if math.abs(s.x)>6.5 or s.forward < -3.5 or s.forward>11 or math.abs(s.y)>13 then return nil end
    return (p.first-s.time)/s.speed
end
function Slam.routes(dx,dz)
    local distance=math.sqrt(dx*dx+dz*dz)
    if distance<.05 or distance>=Slam.safeDistance then return {} end
    local routes={}
    -- 径向退开优先；两条斜退路线用于避开墙体。落点远离敌人，避免其转向后仍在命中箱内。
    for _,angle in ipairs({0,math.pi/4,-math.pi/4}) do
        local x=(dx*math.cos(angle)-dz*math.sin(angle))/distance
        local z=(dx*math.sin(angle)+dz*math.cos(angle))/distance
        local along=dx*x+dz*z
        local length=-along+math.sqrt(along*along+Slam.safeDistance^2-distance^2)+.5
        table.insert(routes,{x=x,z=z,length=length,side=1})
    end
    return routes
end
function Slam.choose(routes)
    local best
    for _,route in ipairs(routes) do
        if route.clear and (not best or route.length<best.length) then best=route end
    end
    return best
end
function Slam.window(remaining,travel,latency,held)
    local budget=travel+(held and math.clamp(latency*.5,.025,.1) or 0)+.02
    return remaining-math.clamp(latency*.5,.03,.19)>=budget,budget
end
function Slam.motion(s)
    if s.manual or s.blocked or s.damaged or not s.alive or s.elapsed>1.2 then return "abort" end
    if not s.playing or s.time>s.last+.12 then return "done" end
    if s.distance>=Slam.safeDistance then return "hold" end
    if not s.path then return "wait" end
    return "move"
end
-- FINDER_SLAM_END

-- FINDER_JUMP_BEGIN
local Jump={}
function Jump.isAnimation(id)
    return type(id)=="string" and id:match("%d+")=="125750702"
end
function Jump.observe(record,now,time,seeded)
    if seeded or time<0 or time>.06 or not record or record.profile.combo~=3 or record.consumed
        or now<record.seenAt or now-record.seenAt>1.25 then return nil end
    return {record=record,at=now}
end
function Jump.window(jump,latest,now,timing,lastDamageAt)
    if not jump or jump.consumed or latest~=jump.record or now<jump.at or now-jump.at>.12 then return false end
    local r=jump.record
    if r.consumed or not (r.gapValid or r.whiffValid) or (lastDamageAt or -math.huge)>=r.seenAt then return false end
    if not (r.gapReady or r.finished or r.interruptReady) then return false end
    local hit=timing and timing.HitTime
    hit=type(hit)=="table" and hit[1] or hit
    return type(hit)=="number",hit
end
function Jump.select(entries,now,timing,lastDamageAt,preferred)
    local best
    for _,e in ipairs(entries) do
        local ready,hit=Jump.window(e.jump,e.record,now,timing,lastDamageAt)
        local far=ready and e.interruptReachable and e.jumpRoute and e.jumpRoute.kind=="advance"
            and e.jumpTravel and e.jumpTravel<=hit-.035
        if ready and (not preferred or e.player==preferred) and (e.eligible or far) and not e.unknown and not e.otherAttack then
            local contested=false
            for _,other in ipairs(entries) do
                if other~=e and (other.attack or other.preempt or other.unknown) then contested=true; break end
            end
            if not contested and (not best or e.distance<best.distance) then
                best=e
                e.interruptStyle=e.eligible and "front" or "advance"
                if e.eligible then e.interruptRoute=nil else e.interruptRoute=e.jumpRoute end
                e.interruptDeadline=e.jump.at+.287
                e.interruptSource="third_jump"
            end
        end
    end
    return best
end
function Jump.landingGeometry(s)
    -- height 明确为目标减自己的高度，不能直接使用朝向自己的 toward.Y。
    return not s.disabled and s.visible and s.distance<=s.range and s.height>4 and s.height<=9
end
function Jump.waitForLanding(action,entry,now)
    -- 起跳抢断命中后仅保留续拳机会；真正出拳仍须满足原 4 格高度门槛。
    return action and action.phase=="struck" and action.jumpOpportunity and entry
        and action.player==entry.player and action.shot and action.shot.target==entry.character
        and not entry.chainEligible and entry.landingEligible and Contact.canContinue(action.shot,now)
end
-- FINDER_JUMP_END

-- FINDER_FLANK_BEGIN
local Flank = {}
function Flank.behind(dx,dz,fx,fz,range,height)
    local distance=math.sqrt(dx*dx+dz*dz)
    local facingLength=math.sqrt(fx*fx+fz*fz)
    if distance<.2 or facingLength<.01 then return false end
    local dot=(dx*fx+dz*fz)/(distance*facingLength)
    return distance<=range and math.abs(height)<=4 and dot<=-.55, dot
end
function Flank.steer(dx,dz,radius,side)
    local distance=math.sqrt(dx*dx+dz*dz)
    if distance<.2 then return nil end
    local radial=math.clamp((radius-distance)*.45,-1.2,1.2)
    local x=(dz*side+dx*radial)/distance
    local z=(-dx*side+dz*radial)/distance
    local length=math.sqrt(x*x+z*z)
    return x/length,z/length
end
function Flank.arc(dx,dz,fx,fz,radius,side)
    local start=math.atan2(dx,dz)
    local finish=math.atan2(-fx,-fz)
    local angle=((finish-start)*side)%(2*math.pi)
    local distance=math.sqrt(dx*dx+dz*dz)
    local count=math.max(1,math.ceil(angle/(math.pi/12)))
    local points={}
    for i=1,count do
        local t=i/count
        local r=distance+(radius-distance)*math.min(1,t*3)
        local a=start+angle*side*t
        table.insert(points,{x=math.sin(a)*r,z=math.cos(a)*r})
    end
    return {side=side,angle=angle,points=points}
end
function Flank.chooseRoute(right,left)
    if right.clear and left.clear then return right.angle<=left.angle+.12 and right or left end
    if right.clear then return right end
    if left.clear then return left end
    return nil
end
function Flank.travelTime(length,speed)
    local rate=10*math.log(2)/1.265
    local fraction=length*rate/(speed or 200.348764)
    if fraction>=.9 or fraction<0 then return math.huge end
    return -math.log(1-fraction)/rate+.04
end
function Flank.reason(s)
    if not s.active then return "请先按 F6 开始" end
    if not s.ready then return "侧闪接口未就绪" end
    if s.manual then return "手动操作优先" end
    if s.blocked then return "自身状态暂不可侧闪" end
    if s.threat then return "附近有攻击威胁，优先防御" end
    if s.cooldown then return "等待游戏侧闪冷却" end
    if s.flank then
        if not s.targetAlive or s.protected then return "目标未就绪或受保护" end
        if not s.targetBlocking and not s.exposed then return "等待格挡破绽或背面暴露" end
        if s.distance<2.5 or s.distance>11 or math.abs(s.height)>3 then return "等待进入绕后距离 2.5–11 格" end
        if not s.clear then return "绕后路线有障碍或落差" end
    end
    return nil
end
function Flank.cooldownReady(state,cooldowns,dashing)
    return not state.CheckState("EvasiveAvailable") and not dashing.SideDashing and not dashing.FrontBackDashing
        and (not cooldowns.SideDash or state.CheckState("NoDashCooldown"))
end
function Flank.nativeReady(state,cooldowns,dashing)
    return not state.CheckState("NoDash") and Flank.cooldownReady(state,cooldowns,dashing)
end
function Flank.attackCooling(now,nextAt,noM1,ownGuard)
    -- 自己持有的格挡也会附加 NoM1；先验证真实普攻计时，松防后再让原 Dash 检查状态。
    return now<nextAt or (noM1 and not ownGuard)
end
function Flank.abort(s)
    if s.manual then return "手动操作，结束侧闪" end
    if s.blocked or s.damaged then return "自身受限或受击，结束绕后" end
    if s.threat then return "发现攻击威胁，恢复防御" end
    if s.elapsed>3.5 then return "绕后超时" end
    if s.flank and (not s.alive or s.protected or s.distance>16 or math.abs(s.height)>4) then return "目标离开绕后范围" end
    return nil
end
function Flank.canStrike(s)
    return s.alive and not s.protected and s.behind and s.visible and not s.blocked
        and not s.cooldown and not s.threat and s.punches<(s.chain and 3 or 1) and (s.lastCombo or 0)<3
end
local FlankDriver={}
FlankDriver.__index=FlankDriver
function FlankDriver.new() return setmetatable({owned=nil,adapter=nil,count=0},FlankDriver) end
function FlankDriver:takeFrom(other)
    if self.owned or not other.owned or other.owned.Parent~=other.root then return false end
    self.owned,self.adapter,self.root=other.owned,other.adapter,other.root
    other.owned,other.adapter,other.root=nil,nil,nil
    return true -- 复用已经由脚本发起的侧闪，不调用第二次 Dash，也不重置冷却。
end
function FlankDriver:launch(a,root,side)
    if self.owned or root:FindFirstChild("DashVelocity") or root:FindFirstChild("FrontDashVelocity") then return false end
    if not a.dashReady() then return false end
    a.dash(side==1 and "Right" or "Left",false) -- 不使用跳过状态检查的 bool2=true。
    local velocity=root:FindFirstChild("DashVelocity")
    if not velocity or not velocity:IsA("BodyVelocity") then return false end
    self.owned,self.adapter,self.root=velocity,a,root
    self.count+=1
    return true
end
function FlankDriver:release(brake)
    local velocity,a,root=self.owned,self.adapter,self.root
    self.owned,self.adapter,self.root=nil,nil,nil
    if velocity and velocity.Parent==root then
        if a.cancelDash then pcall(a.cancelDash) end
        -- 只在成功到达预定近身位置时制动本次侧闪的水平惯性；受击/手动中止时保留游戏的速度。
        -- 同时出现其他速度控制器时不制动，避免覆盖击退或技能运动。
        if brake then
            local exclusive=true
            for _,child in ipairs(root:GetChildren()) do
                if child~=velocity and (child:IsA("BodyMover") or child:IsA("LinearVelocity")
                    or child:IsA("VectorForce")) then exclusive=false; break end
            end
            if exclusive then
                local current=root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity=current*Vector3.new(0,1,0)
            end
        end
        -- 仅结束本次脚本调用产生的侧闪；不删除玩家或游戏另外发起的速度对象。
        velocity:Destroy()
    end
end
-- FINDER_FLANK_END

local emergencyCleanup
local startupStage = "准备启动"
local function diagnostic(message)
    local text = "ClientFinder v3.18\n地图："..tostring(game.PlaceId).." / 游戏："..tostring(game.GameId)
        .."\n阶段：" .. startupStage .. "\n" .. tostring(message)
    print("[客户端自动找人 v3.18] " .. tostring(message))
    -- Real 的可选本地文件接口：只写启动/停止/错误事件，不在逐帧循环里写文件。
    if type(writefile) == "function" then pcall(writefile, "ClientFinder-diagnostics.txt", text) end
end
diagnostic("脚本已进入，正在创建面板")
local function traceback(reason)
    return debug and debug.traceback and debug.traceback(tostring(reason), 2) or tostring(reason)
end
local function main()
    startupStage = "获取客户端和 PlayerGui"
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Input = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local HttpService = game:GetService("HttpService")
    local me = assert(Players.LocalPlayer, "请在已经进入游戏的客户端运行")
    local parent = assert(me:WaitForChild("PlayerGui", 15), "PlayerGui 尚未加载")
    local GUI_NAME, STEP_NAME = "LocalClientFinderGui", "LocalClientFinderUpdate"
    local oldError = parent:FindFirstChild("ClientFinderError")
    if oldError then oldError:Destroy() end
    local previous = parent:FindFirstChild(GUI_NAME)
    if previous then
        local shutdown = previous:FindFirstChild("Shutdown")
        if shutdown and shutdown:IsA("BindableFunction") then shutdown:Invoke() else previous:Destroy() end
    end
    local config = { range = 250, stopDistance = 6, response = 24, visibleOnly = true,
        chase = false, face = true, attack = false, attackRange = 7, defense = false, defenseRange = 18, preempt = true,
        counter = true, gap = false, chain = true, flank = false, interrupt = true, interruptStyle = "advance", interruptRange = 14, evade = false, jump = true }
    local active, closed, focused = false, false, true
    local target, cameraRecord, movingHuman
    local connections, players = {}, Players:GetPlayers()
    local scanTimer, uiTimer, ticks, measureTimer, updateHz = 0, 0, 0, 0, 0
    local candidateCount, lastCostMs, message = 0, 0, "已就绪：点击开始找人"
    local refresh, stop, cleanup
    local driver = AttackDriver.new()
    local guard = DefenseDriver.new()
    local watchers, watchTimer, observedAttacks = {}, 0.05, 0
    local preemptCount, lastDefenseDelay = 0, nil
    local defenseMessage = "自动防御已关闭"
    local defenseTarget, defenseBusy
    local counterAction, counterCount = nil, 0
    local interruptCount=0
    local pendingShot,hitCount=nil,0
    local counterMessage = "等待挡中或空招，抓间隙连击"
    local blockFeedback, lastDamageAt = nil, -math.huge
    local flankDriver=FlankDriver.new()
    local evadeDriver=FlankDriver.new()
    local evadeAction,evadeCount=nil,0
    local flankAction,dashRequested,flankNextAt,flankAttackCount=nil,false,0,0
    local flankMessage="Z 向右侧闪；开启绕后破防后自动绕行攻击"
    local adapter, rotationRecord
    local loadGeneration, loading, manualUntil = 0, false, 0
    local attackMessage, adapterMessage = "自动普攻已关闭", "未加载"
    local characterNames = { "MartialArtist", "Jun", "Shinji", "VirusOverlord", "Black", "Kratos", "KingOfCurses" }
    local function create(className, properties, owner)
        local item = Instance.new(className)
        for key, value in pairs(properties) do item[key] = value end
        item.Parent = owner
        return item
    end
    startupStage = "创建面板"
    local gui = create("ScreenGui", { Name = GUI_NAME, ResetOnSpawn = false, DisplayOrder = 1100,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, parent)
    -- 面板初始化失败时也能移除已经创建的实例。
    emergencyCleanup = function()
        RunService:UnbindFromRenderStep(STEP_NAME)
        for _, connection in ipairs(connections) do connection:Disconnect() end
        gui:Destroy()
    end
    local panel = create("Frame", { Name = "Panel", Position = UDim2.new(1, -320, 0, 86),
        Size = UDim2.fromOffset(304, 844), BackgroundColor3 = Color3.fromRGB(20, 28, 39),
        BorderSizePixel = 0 }, gui)
    create("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
    local function label(name, text, x, y, width, height)
        return create("TextLabel", { Name = name, Text = text, Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1, TextSize = 14,
            TextColor3 = Color3.fromRGB(222, 233, 243), TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham }, panel)
    end
    local function button(name, text, x, y, width, height)
        local item = create("TextButton", { Name = name, Text = text, Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(width, height), TextSize = 14, TextWrapped = true,
            BackgroundColor3 = Color3.fromRGB(43, 76, 98), TextColor3 = Color3.fromRGB(242, 248, 255),
            BorderSizePixel = 0, Font = Enum.Font.Gotham }, panel)
        create("UICorner", { CornerRadius = UDim.new(0, 6) }, item)
        return item
    end
    local title = label("Title", "自动找人 · 攻防 v3.18", 12, 4, 240, 34)
    title.TextSize, title.Active = 18, true
    local close = button("Close", "×", 262, 7, 30, 28)
    local toggle = button("Toggle", "开始找人 · F6", 12, 45, 185, 34)
    local halt = button("Stop", "停止 · F9", 204, 45, 88, 34)
    halt.BackgroundColor3 = Color3.fromRGB(136, 50, 65)
    local targetLabel = label("Target", "目标：未选择", 12, 86, 280, 43)
    local chase = button("Chase", "自动追击：关", 12, 138, 136, 33)
    local visibility = button("Visibility", "视线筛选：开", 156, 138, 136, 33)
    local speed = button("Response", "镜头响应：快", 12, 179, 136, 33)
    local reselect = button("Reselect", "重新选最近目标", 156, 179, 136, 33)
    label("RangeLabel", "找人范围", 12, 224, 64, 30)
    label("StopDistanceLabel", "追击停距", 155, 224, 67, 30)
    local function box(name, value, x)
        return create("TextBox", { Name = name, Text = tostring(value), Position = UDim2.fromOffset(x, 224),
            Size = UDim2.fromOffset(68, 30), ClearTextOnFocus = false, TextSize = 14,
            TextColor3 = Color3.fromRGB(240, 248, 255), BackgroundColor3 = Color3.fromRGB(33, 49, 64),
            BorderSizePixel = 0, Font = Enum.Font.Gotham }, panel)
    end
    local rangeBox, stopBox = box("Range", config.range, 78), box("StopDistance", config.stopDistance, 224)
    local attackButton = button("Attack", "自动普攻：关 · F7", 12, 264, 185, 34)
    label("AttackRangeLabel", "出拳距离", 205, 259, 87, 20).TextSize = 12
    local attackRangeBox = box("AttackRange", config.attackRange, 224)
    attackRangeBox.Position, attackRangeBox.Size = UDim2.fromOffset(205, 280), UDim2.fromOffset(87, 26)
    local attackStatus = label("AttackStatus", attackMessage, 12, 311, 280, 42)
    attackStatus.TextColor3 = Color3.fromRGB(255, 215, 146)
    local defenseButton = button("Defense", "自动防御：关 · F8", 12, 359, 185, 34)
    label("DefenseRangeLabel", "警戒距离", 205, 354, 87, 20).TextSize = 12
    local defenseRangeBox = box("DefenseRange", config.defenseRange, 224)
    defenseRangeBox.Position, defenseRangeBox.Size = UDim2.fromOffset(205, 375), UDim2.fromOffset(87, 26)
    local preemptButton = button("Preempt", "近身预防：开", 12, 407, 136, 30)
    local counterButton = button("Counter", "自动反击：开 · F10", 156, 407, 136, 30)
    local gapButton = button("GapMode", "反击时机：挡中", 12, 445, 136, 30)
    local chainButton = button("ChainMode", "命中连击：三段", 156, 445, 136, 30)
    local dashButton = button("Dash", "向右侧闪 · Z", 12, 483, 136, 30)
    local flankButton = button("Flank", "绕后破防：关", 156, 483, 136, 30)
    local interruptButton=button("Interrupt", "间隙抢断：开", 12, 517, 136, 30)
    local interruptStyleButton=button("InterruptStyle", "方式：直进", 156, 517, 136, 30)
    local flankStatus = label("FlankStatus", flankMessage, 12, 555, 280, 38)
    flankStatus.TextSize = 12
    local defenseStatus = label("DefenseStatus", defenseMessage, 12, 597, 280, 42)
    defenseStatus.TextColor3 = Color3.fromRGB(143, 219, 255)
    local statusLabel = label("Status", message, 12, 643, 280, 35)
    local metrics = label("Metrics", "选敌 20 Hz · 位置/镜头每帧更新", 12, 683, 280, 36)
    metrics.TextSize = 12
    local evadeButton=button("SlamEvade", "下砸避让：关", 12, 727, 136, 30)
    local jumpButton=button("JumpInterrupt", "起跳抢断：开", 156, 727, 136, 30)
    local faceButton=button("FaceTarget", "面向目标：开 · F5", 12, 765, 280, 30)
    label("Help", "F6 开始 / F7 普攻 / F8 防御 / F9 全停\nF5 面向目标；F10 自动反击", 12, 803, 280, 34).TextSize = 12
    local panelScale = create("UIScale", {Scale=1}, panel)
    local function fitPanel()
        local size = gui.AbsoluteSize
        local scale = math.clamp(math.min((size.Y - 24) / 844, (size.X - 24) / 304), 0.3, 1)
        panelScale.Scale = scale
        panel.Position = UDim2.new(1, -304 * scale - 12, 0, 12)
    end
    fitPanel()
    local marker = create("Highlight", { Name = "ClientFinderTarget", Enabled = false,
        FillTransparency = 0.9, OutlineTransparency = 0, OutlineColor = Color3.fromRGB(65, 219, 255),
        DepthMode = Enum.HighlightDepthMode.Occluded }, gui)

    local function parts(owner)
        if not owner or owner.Parent ~= Players then return nil end
        local character = owner.Character
        if not character or not character:IsDescendantOf(Workspace) then return nil end
        local human = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if not human or not root or not root:IsA("BasePart") or human.Health <= 0
            or human:GetState() == Enum.HumanoidStateType.Dead then return nil end
        return character, human, root
    end
    local traceEvents, tracePending, monitorCharacter = {}, false, nil
    local monitorConnections, traceGate = {}, nil
    local guardHistory, guardSampleAt = {}, -math.huge
    local function flushTrace()
        tracePending = false
        if type(writefile) ~= "function" then return end
        pcall(function()
            writefile("ClientFinder-combat-trace.json", HttpService:JSONEncode({version="3.18",
                placeId=game.PlaceId,gameId=game.GameId,events=traceEvents}))
        end)
    end
    local function trace(event, details)
        local character, human, root = parts(me)
        local row = {t=os.clock(), event=event, details=details, active=active, preempt=config.preempt,
            autoAttack=config.attack, counter=config.counter, gap=config.gap, chain=config.chain,flank=config.flank,interrupt=config.interrupt,
            interruptStyle=config.interruptStyle,
            slamEvade=config.evade,jumpInterrupt=config.jump,evadePhase=evadeAction and evadeAction.phase,
            weaving=counterAction and counterAction.weaving,
            flankPhase=flankAction and flankAction.phase,
            counterPhase=counterAction and counterAction.phase,
            held=guard.held ~= nil, health=human and human.Health, guardLatency=guard.latency,releaseLatency=guard.releaseLatency,
            blocking=character and character:GetAttribute("Blocking"), gate=traceGate}
        row.faceTarget=config.face
        if event=="DAMAGE" then row.guardHistory=table.clone(guardHistory) end
        if adapter then
            row.blockHeld = adapter.state.BlockHeld
            row.states = {}
            for _, key in ipairs({"NoBlock","Freeze","Ragdoll","NoRotate","NoM1"}) do
                row.states[key] = adapter.state.CheckState(key)
            end
        end
        row.nearby = {}
        if root then
            for _, other in ipairs(players) do
                if other ~= me then
                    local c, h, r = parts(other)
                    if r then
                        local d = r.Position - root.Position
                        local flat = Vector3.new(d.X, 0, d.Z)
                        if d.Magnitude <= (event=="DAMAGE" and 32 or 18) then
                            local info = {id=other.UserId, distance=d.Magnitude, height=d.Y,
                                facing=flat.Magnitude > 0.05 and root.CFrame.LookVector:Dot(flat.Unit) or 1,
                                enemyFacing=flat.Magnitude > 0.05 and r.CFrame.LookVector:Dot(-flat.Unit) or 1,
                                blocking=c:GetAttribute("Blocking"),ragdolled=c:GetAttribute("Ragdolled"),
                                protected=c:GetAttribute("GodMode") or c:FindFirstChildOfClass("ForceField")~=nil,
                                health=h.Health, animations={}}
                            local animator = h:FindFirstChildOfClass("Animator")
                            if animator then
                                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                                    local a = track.Animation
                                    if a then table.insert(info.animations,{id=a.AnimationId,time=track.TimePosition,
                                        speed=track.Speed,priority=track.Priority.Name,known=Defense.profile(a.AnimationId) ~= nil}) end
                                end
                            end
                            table.insert(row.nearby, info)
                        end
                    end
                end
            end
        end
        table.insert(traceEvents, row)
        if #traceEvents > 160 then table.remove(traceEvents,1) end
        if not tracePending then
            tracePending = true
            task.delay(0.25, function() if tracePending then flushTrace() end end)
        end
    end
    local function sampleGuardMotion(character,root)
        local now=os.clock()
        if now-guardSampleAt<.01 then return end
        guardSampleAt=now
        local owner=defenseTarget or target
        local _,_,enemyRoot=parts(owner)
        local look=root.CFrame.LookVector
        local sample={t=now,position={root.Position.X,root.Position.Y,root.Position.Z},look={look.X,look.Z},
            target=owner and owner.UserId,held=guard.held~=nil,blocking=character:GetAttribute("Blocking"),
            manualFor=math.max(0,manualUntil-now),keyF=Input:IsKeyDown(Enum.KeyCode.F),
            mouse1=Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)}
        if adapter and adapter.character==character then
            sample.noRotate=adapter.state.CheckState("NoRotate")
            sample.noBlock=adapter.state.CheckState("NoBlock")
            sample.freeze=adapter.state.CheckState("Freeze")
        end
        if enemyRoot then
            local p=enemyRoot.Position
            sample.enemy={p.X,p.Y,p.Z}
            local watch=watchers[owner]
            if watch and watch.guardAim and now-watch.guardAim.at<=.05 then sample.aim=watch.guardAim end
            sample.dashing=watch and DashGuard.active(watch.dash,now) or false
        end
        table.insert(guardHistory,sample)
        if #guardHistory>60 then table.remove(guardHistory,1) end
    end
    local function clearMonitor()
        for _, connection in ipairs(monitorConnections) do connection:Disconnect() end
        monitorConnections, monitorCharacter = {}, nil
    end
    local function ensureMonitor(character, human)
        if monitorCharacter == character then return end
        clearMonitor()
        monitorCharacter = character
        local lastHealth = human.Health
        table.insert(monitorConnections, human.HealthChanged:Connect(function(health)
            local loss = lastHealth - health
            lastHealth = health
            if active and loss > 0 then
                lastDamageAt=os.clock()
                if pendingShot then pendingShot.cancelled=true end
                pcall(trace,"DAMAGE",{loss=loss})
            end
        end))
        table.insert(monitorConnections, character:GetAttributeChangedSignal("Blocking"):Connect(function()
            guard:observeRelease(character:GetAttribute("Blocking"),os.clock())
            if active then pcall(trace,"BLOCKING",{value=character:GetAttribute("Blocking")}) end
        end))
    end
    local function releaseMovement(manual)
        local human = movingHuman
        movingHuman = nil
        if human and human.Parent and not manual then human:Move(Vector3.zero, false) end
    end
    local function releaseCamera()
        local saved = cameraRecord
        cameraRecord = nil
        if saved and saved.camera.Parent and saved.camera.CameraType == Enum.CameraType.Scriptable then
            if saved.subject and saved.subject.Parent then saved.camera.CameraSubject = saved.subject end
            saved.camera.CameraType = saved.kind
        end
    end
    local function releaseRotation()
        rotationRecord = Facing.release(rotationRecord)
    end
    local function releaseAttack()
        local ok, reason = driver:release()
        releaseRotation()
        if not ok then warn("[自动普攻] 松开请求失败：" .. tostring(reason)) end
    end
    local function cancelFlank(reason)
        local action=flankAction
        flankAction,dashRequested=nil,false
        flankDriver:release()
        if action then
            if action.shot then action.shot.cancelled=true end
            driver:release()
            releaseRotation()
            releaseCamera()
            flankNextAt=math.max(flankNextAt,os.clock()+.35)
            pcall(trace,"FLANK_END",{reason=reason,phase=action.phase,punches=action.punches})
        end
        flankMessage=reason or "等待侧闪机会"
    end
    local function cancelCounter(reason)
        if counterAction then
            local shot=counterAction.shot
            local shotStatus=shot and {confirmedAt=shot.confirmedAt,cancelled=shot.cancelled or false,
                sentAt=shot.sentAt,deadline=shot.deadline,combo=shot.combo}
            if counterAction.shot then counterAction.shot.cancelled=true end
            if counterAction.approachDash or counterAction.weaving then flankDriver:release(); releaseCamera(); releaseRotation() end
            counterAction.record.consumed = true
            pcall(trace,"COUNTER_END",{reason=reason,phase=counterAction.phase,player=counterAction.player.UserId,
                jump=counterAction.jumpOpportunity or false,punches=counterAction.punches,shot=shotStatus,
                entry=counterAction.lastEntryStatus})
            counterAction = nil
        end
        counterMessage = reason or "等待挡中或空招，抓间隙连击"
    end
    local function cancelEvade(reason,brake)
        local action=evadeAction
        evadeAction=nil
        evadeDriver:release(brake)
        if action then
            releaseMovement(false); releaseCamera(); releaseRotation()
            pcall(trace,"SLAM_END",{reason=reason,player=action.player.UserId,phase=action.phase,
                elapsed=os.clock()-action.startedAt})
        end
    end
    local function releaseDefense()
        blockFeedback = nil
        cancelEvade("防御暂停")
        cancelCounter("反击已暂停")
        local hadControl = guard.held ~= nil or defenseBusy
        local ok, reason = guard:release()
        defenseTarget, defenseBusy = nil, false
        if hadControl then releaseRotation() end
        if not ok then warn("[自动防御] 松开失败：" .. tostring(reason)) end
    end
    local function clearWatchers()
        for key, watch in pairs(watchers) do watch.connection:Disconnect(); watchers[key] = nil end
        watchTimer = 0.05
    end
    local function bindNativeDash(character,state)
        assert(type(getgc)=="function" and type(getfenv)=="function" and type(debug.getupvalues)=="function",
            "当前环境不支持读取原侧闪接口")
        local controls=assert(character:FindFirstChild("Controls"),"Controls 未加载")
        local root=assert(character:FindFirstChild("HumanoidRootPart"),"根部未加载")
        local human=assert(character:FindFirstChildOfClass("Humanoid"),"Humanoid 未加载")
        local found={Dash={},CancelDash={},SlowDashVelocities={}}
        for _,fn in ipairs(getgc()) do
            if type(fn)=="function" then
                local ok,env=pcall(getfenv,fn)
                if ok and type(env)=="table" and rawget(env,"script")==controls then
                    local named,name=pcall(debug.info,fn,"n")
                    if named and found[name] then table.insert(found[name],fn) end
                end
            end
        end
        for name,list in pairs(found) do assert(#list==1,"原侧闪接口不唯一："..name) end
        local dash,cancel,slow=found.Dash[1],found.CancelDash[1],found.SlowDashVelocities[1]
        local values=debug.getupvalues(dash)
        local seen,cooldowns,dashing={},nil,nil
        for _,value in pairs(values) do
            seen[value]=true
            if type(value)=="table" and type(rawget(value,"SideDash"))=="boolean"
                and type(rawget(value,"FrontBackDash"))=="boolean" then cooldowns=value end
            if type(value)=="table" and type(rawget(value,"SideDashing"))=="boolean"
                and type(rawget(value,"FrontBackDashing"))=="boolean" then dashing=value end
        end
        local camera=Workspace.CurrentCamera
        assert(seen[root] and seen[human] and seen[character] and seen[state] and seen[camera]
            and seen[character:FindFirstChild("Network")] and cooldowns and dashing,"侧闪绑定不属于当前角色或接口已变化")
        local ownsRoot,ownsSlow=false,false
        for _,value in pairs(debug.getupvalues(slow)) do if value==root then ownsRoot=true end end
        for _,value in pairs(debug.getupvalues(cancel)) do if value==slow then ownsSlow=true end end
        assert(ownsRoot and ownsSlow,"取消侧闪接口未绑定当前角色")
        return {dash=dash,cancelDash=cancel,dashCooldownReady=function() return Flank.cooldownReady(state,cooldowns,dashing) end,
            dashReady=function()
            return me.Character==character and controls.Parent==character and controls.Enabled
                and camera==Workspace.CurrentCamera and human.Health>0 and Flank.nativeReady(state,cooldowns,dashing)
        end}
    end
    local function prepareAttack(character)
        if pendingShot then pendingShot.cancelled=true end
        pendingShot=nil
        loadGeneration += 1
        local generation = loadGeneration
        cancelFlank("角色模块更新，结束侧闪")
        releaseDefense()
        adapter, loading, adapterMessage = nil, true, "正在加载游戏攻防模块"
        releaseAttack()
        task.delay(8, function()
            if not closed and loading and generation == loadGeneration then
                loadGeneration += 1
                loading, adapterMessage = false, "加载超时；关闭再开启普攻或防御重试"
            end
        end)
        task.spawn(function()
            local ok, result = pcall(function()
                local placeReason=Compat.placeReason(game.PlaceId,game.GameId)
                assert(not placeReason,placeReason)
                assert(character and me.Character == character, "自己的角色未加载")
                local selected = character:GetAttribute("SelectedCharacter")
                local name = characterNames[selected]
                assert(name, "SelectedCharacter 尚未加载或角色未适配")
                local modules = assert(ReplicatedStorage:FindFirstChild("Modules"), "Modules 未加载")
                local assets = assert(ReplicatedStorage:FindFirstChild("Assets"), "Assets 未加载")
                local storage = assert(assets:FindFirstChild("CharacterStorage"), "CharacterStorage 未加载")
                local folder = assert(storage:FindFirstChild(name), "角色文件夹未加载")
                local stateModule = assert(modules:FindFirstChild("ClientState"), "ClientState 未加载")
                local moveModule = assert(folder:FindFirstChild("M1"), "M1 模块未加载")
                local remote = assert(character:FindFirstChild("Network"), "角色 Network 未加载")
                assert(remote:IsA("RemoteEvent"), "角色 Network 类型不兼容")
                local state, moves = require(stateModule), require(moveModule)
                local ids = require(assert(modules:FindFirstChild("UniqueIdGenerator"), "UniqueIdGenerator 未加载"))
                local moduleReason=Compat.moduleReason(state,moves,ids)
                assert(not moduleReason,moduleReason)
                local function stopBlockAnimation()
                    local id = character:GetAttribute("BlockAnimationId")
                    local h = character:FindFirstChildOfClass("Humanoid")
                    local animator = h and h:FindFirstChildOfClass("Animator")
                    if type(id) ~= "string" or not animator then return end
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        if track.Animation and track.Animation.AnimationId == id then track:Stop() end
                    end
                end
                local dashOK,native=pcall(bindNativeDash,character,state)
                local replication
                local gameModule=modules:FindFirstChild("Game")
                if gameModule then
                    local loaded,api=pcall(require,gameModule)
                    if loaded and type(api)=="table" and type(api.Holder)=="table" and type(api.Entity)=="table"
                        and type(api.Holder.GetEntityFromPlayer)=="function" and type(api.Entity.GetCFrame)=="function"
                        and type(api.Entity.GetTargetRenderTime)=="function" then replication=api end
                end
                return { character = character, selected = selected, state = state, moves = moves, remote = remote, name = name,maxCombo=3,
                    replication=replication,
                    canChain=function(combo,now,victim) return Contact.canStart(pendingShot,combo,now,victim) end,
                    beforeAttack=function(_,combo,now,timing,victim)
                        pendingShot=Contact.shot(victim,combo,now,timing,selected)
                        return pendingShot
                    end,
                    dash=dashOK and native.dash or nil,cancelDash=dashOK and native.cancelDash or nil,
                    dashReady=dashOK and native.dashReady or nil,dashError=not dashOK and tostring(native) or nil,
                    dashCooldownReady=dashOK and native.dashCooldownReady or nil,
                    uniqueId = ids.GetUniqueId, stopBlockAnimation = stopBlockAnimation,
                    isBlocking=function() return character:GetAttribute("Blocking") end,
                    guardEvent = function(event,n) trace(event,{n=n}) end }
            end)
            if closed or generation ~= loadGeneration then return end
            loading = false
            if ok and me.Character == character then adapter, adapterMessage = result, result.name .. " 攻防就绪"
            else adapterMessage = "加载失败：" .. tostring(result); warn("[自动普攻] " .. adapterMessage) end
            diagnostic(adapterMessage)
            pcall(trace,ok and "ADAPTER_READY" or "ADAPTER_ERROR",{message=adapterMessage,
                placeId=game.PlaceId,gameId=game.GameId})
            if ok then
                flankMessage=result.dash and "原侧闪已就绪；Z 侧闪，绕后开关可自动破防" or ("侧闪不可用："..tostring(result.dashError))
                pcall(trace,"DASH_BIND",{ready=result.dash~=nil,error=result.dashError})
                pcall(trace,"REPLICATION_AIM_BIND",{ready=result.replication~=nil})
            end
        end)
    end
    local function combatBlocked(character, human, root, releasedOwnGuard)
        if human.Sit or human.PlatformStand or root.Anchored or character:GetAttribute("Ragdolled") then return true end
        if not adapter or adapter.character ~= character then return false end
        local state = adapter.state
        return state.BlockHeld or (not releasedOwnGuard and character:GetAttribute("Blocking")) or state.CheckState("Freeze")
            or state.CheckState("Ragdoll") or state.CheckState("Rolling") or state.CheckState("NoRotate")
            or root:FindFirstChild("DashVelocity") ~= nil or root:FindFirstChild("RollVelocity") ~= nil
    end
    refresh = function()
        if closed then return end
        toggle.Text = active and "找人中 · F6 暂停" or "开始找人 · F6"
        toggle.BackgroundColor3 = active and Color3.fromRGB(32, 128, 91) or Color3.fromRGB(43, 76, 98)
        chase.Text = "自动追击：" .. (config.chase and "开" or "关")
        faceButton.Text = "面向目标：" .. (config.face and "开" or "关") .. " · F5"
        faceButton.BackgroundColor3 = config.face and Color3.fromRGB(35,111,148) or Color3.fromRGB(43,76,98)
        visibility.Text = "视线筛选：" .. (config.visibleOnly and "开" or "关")
        speed.Text = "镜头响应：" .. (config.response == 24 and "快" or "柔和")
        attackButton.Text = "自动普攻：" .. (config.attack and "开" or "关") .. " · F7"
        attackButton.BackgroundColor3 = config.attack and Color3.fromRGB(158, 93, 37) or Color3.fromRGB(43, 76, 98)
        attackStatus.Text = (config.counter and config.defense and not config.attack and counterMessage or attackMessage)
            .. string.format("\n出拳 %d · 反击 %d · 命中确认 %d", driver.count, counterCount,hitCount)
        defenseButton.Text = "自动防御：" .. (config.defense and "开" or "关") .. " · F8"
        defenseButton.BackgroundColor3 = config.defense and Color3.fromRGB(35, 111, 148) or Color3.fromRGB(43, 76, 98)
        preemptButton.Text = "近身预防：" .. (config.preempt and "开" or "关")
        counterButton.Text = "自动反击：" .. (config.counter and "开" or "关") .. " · F10"
        counterButton.BackgroundColor3 = config.counter and Color3.fromRGB(138, 87, 43) or Color3.fromRGB(43, 76, 98)
        gapButton.Text = "反击时机：" .. (config.gap and "挡中/空招" or "收尾")
        chainButton.Text = "命中连击：" .. (config.chain and "三段" or "单拳")
        interruptButton.Text="间隙抢断："..(config.interrupt and "开" or "关")
        interruptButton.BackgroundColor3=config.interrupt and Color3.fromRGB(116,74,139) or Color3.fromRGB(43,76,98)
        local front=Interrupt.frontOnly(config.interruptStyle)
        local advance=config.interruptStyle=="advance"
        interruptStyleButton.Text=front and "方式：正面" or (advance and "方式：直进" or "方式：侧闪")
        dashButton.Text = not Interrupt.canFlank(config.interruptStyle) and "测试中：停用 Z" or (config.flank and "绕后一次 · Z" or "向右侧闪 · Z")
        flankButton.Text = not Interrupt.canFlank(config.interruptStyle) and "测试中：禁绕后" or ("绕后破防："..(config.flank and "开" or "关"))
        flankButton.BackgroundColor3 = Interrupt.canFlank(config.interruptStyle) and config.flank and Color3.fromRGB(102,77,153) or Color3.fromRGB(43,76,98)
        flankStatus.Text = (front and "正面抢断测试：自动侧闪、绕后与空招接近已停用"
            or (advance and string.format("直线侧闪+普攻：%.0f–%.0f 格起手，不绕后",config.attackRange,config.interruptRange) or flankMessage))
            ..string.format("\n侧闪 %d 次 · 绕后发起 %d 拳",flankDriver.count,flankAttackCount)
        defenseStatus.Text = defenseMessage .. string.format("\n识别 %d · 格挡请求 %d / 确认 %d", observedAttacks, guard.count, guard.confirmed)
        evadeButton.Text="下砸避让："..(config.evade and "开" or "关")
        jumpButton.Text="起跳抢断："..(config.jump and "开" or "关")
        jumpButton.BackgroundColor3=config.jump and Color3.fromRGB(138,87,43) or Color3.fromRGB(43,76,98)
        evadeButton.BackgroundColor3=config.evade and Color3.fromRGB(116,74,139) or Color3.fromRGB(43,76,98)
        statusLabel.Text = message
        local _, _, ownRoot = parts(me)
        local character, _, enemyRoot = parts(target)
        if target and enemyRoot and ownRoot then
            targetLabel.Text = string.format("%s  @%s\n距离 %.1f 格", target.DisplayName, target.Name,
                (enemyRoot.Position - ownRoot.Position).Magnitude)
        else targetLabel.Text = "目标：未选择 / 角色未加载" end
        marker.Adornee, marker.Enabled = character, active and character ~= nil
        metrics.Text = string.format("更新 %.0f Hz · 本地逻辑 %.2f ms\n举防 %.0f ms / 松防 %.0f ms", updateHz, lastCostMs, guard.latency * 1000, guard.releaseLatency*1000)
    end
    stop = function(reason)
        if pendingShot then pendingShot.cancelled=true end
        if active then pcall(trace,"STOP",{reason=reason}) end
        active, target = false, nil
        cancelFlank("侧闪已停止")
        releaseAttack()
        releaseDefense()
        clearWatchers()
        flushTrace()
        defenseMessage = config.defense and "已暂停防御，F6 重新开始" or "自动防御已关闭"
        attackMessage = config.attack and "已暂停普攻，F6 重新开始" or "自动普攻已关闭"
        releaseMovement(false)
        releaseCamera()
        marker.Enabled, marker.Adornee = false, nil
        message = reason or "已停止，镜头和移动已交回游戏"
        diagnostic(message .. string.format("；已发起 %d 拳；识别 %d 次攻击；格挡请求 %d 次，进入格挡 %d 次；近身预防 %d 次；本地检测至发起 %s ms（不含网络）",
            driver.count, observedAttacks, guard.count, guard.confirmed, preemptCount, tostring(lastDefenseDelay)))
        refresh()
    end
    cleanup = function()
        if closed then return end
        stop("已关闭")
        clearMonitor()
        closed = true
        loadGeneration += 1
        RunService:UnbindFromRenderStep(STEP_NAME)
        for _, connection in ipairs(connections) do connection:Disconnect() end
        gui:Destroy()
    end
    emergencyCleanup = cleanup
    local function fail(reason)
        if closed then return end
        stop("运行出错，已停止；详情见输出")
        warn("[客户端自动找人] " .. tostring(reason))
        statusLabel.Text = "已停止：" .. tostring(reason):sub(1, 160)
        diagnostic("运行错误：" .. tostring(reason))
    end
    local function connect(signal, callback)
        table.insert(connections, signal:Connect(function(...)
            if closed then return end
            local ok, reason = xpcall(callback, traceback, ...)
            if not ok then fail(reason) end
        end))
    end
    create("BindableFunction", { Name = "Shutdown", OnInvoke = cleanup }, gui)
    connect(gui.Destroying, cleanup)
    local function start()
        if active then stop(); return end
        if not focused or Input:GetFocusedTextBox() or GuiService.MenuIsOpen then
            message = "请先回到游戏并关闭聊天或菜单"; refresh(); return
        end
        local character, human, root = parts(me)
        if not root or not human then message = "等待自己的角色存活并加载"; refresh(); return end
        active, target, scanTimer = true, nil, 0.05
        guardHistory,guardSampleAt={},-math.huge
        ensureMonitor(character, human)
        pcall(trace,"START")
        if (config.face or config.attack or config.defense or config.flank) and not adapter and not loading then prepareAttack(me.Character) end
        message = "正在选择附近其他玩家"
        diagnostic("已开始；自动普攻=" .. tostring(config.attack) .. "；自动追击=" .. tostring(config.chase) .. "；自动防御=" .. tostring(config.defense))
        refresh()
    end
    local function ray(origin, direction, exclude)
        if direction.Magnitude < 0.01 then return nil end
        local parameters = RaycastParams.new()
        parameters.FilterType, parameters.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, exclude
        parameters.IgnoreWater, parameters.RespectCanCollide = true, true
        return Workspace:Raycast(origin, direction, parameters)
    end
    local function scan(ownCharacter, ownRoot)
        local records = {}
        for _, other in ipairs(players) do
            if other ~= me then
                local character, _, root = parts(other)
                if root then
                    local distance = (root.Position - ownRoot.Position).Magnitude
                    if distance <= config.range then
                        local visible = true
                        if config.visibleOnly then
                            visible = ray(ownRoot.Position + Vector3.new(0, 1.5, 0),
                                root.Position - ownRoot.Position, {ownCharacter, character}) == nil
                        end
                        table.insert(records, { id = other.UserId, player = other, distance = distance, visible = visible })
                    end
                end
            end
        end
        candidateCount = #records
        local chosen = Core.choose(records, target and target.UserId, config.range, config.visibleOnly)
        target = chosen and chosen.player or nil
    end
    local function cameraStep(ownCharacter, ownRoot, enemyCharacter, enemyRoot, deltaTime)
        local camera = Workspace.CurrentCamera
        if not camera then return end
        if cameraRecord and cameraRecord.camera ~= camera then releaseCamera() end
        if not cameraRecord then
            local offset = camera.CFrame.Position - ownRoot.Position
            cameraRecord = { camera = camera, kind = camera.CameraType, subject = camera.CameraSubject,
                distance = math.clamp(Vector3.new(offset.X, 0, offset.Z).Magnitude, 8, 24),
                height = math.clamp(offset.Y, 4, 10) }
            camera.CameraType = Enum.CameraType.Scriptable
        elseif camera.CameraType ~= Enum.CameraType.Scriptable then
            stop("游戏接管了镜头，已暂停"); return
        end
        local difference = enemyRoot.Position - ownRoot.Position
        local horizontal = Vector3.new(difference.X, 0, difference.Z)
        local direction = horizontal.Magnitude > 0.05 and horizontal.Unit or ownRoot.CFrame.LookVector
        local aim = enemyRoot.Position + Vector3.new(0, 1.5, 0)
        local anchor = ownRoot.Position + Vector3.new(0, 1.5, 0)
        local desired = ownRoot.Position - direction * cameraRecord.distance + Vector3.new(0, cameraRecord.height, 0)
        -- 把相机放到墙前，避免脚本镜头钻入实体墙壁。
        local obstacle = ray(anchor, desired - anchor, {ownCharacter, enemyCharacter})
        if obstacle then desired = obstacle.Position + obstacle.Normal * 0.6 end
        if (aim - desired).Magnitude > 0.05 then
            camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(desired, aim), Core.alpha(config.response, deltaTime))
            camera.Focus = CFrame.new(aim)
        end
    end
    local function manualMovement()
        return Input:IsKeyDown(Enum.KeyCode.W) or Input:IsKeyDown(Enum.KeyCode.A)
            or Input:IsKeyDown(Enum.KeyCode.S) or Input:IsKeyDown(Enum.KeyCode.D)
            or Input:IsKeyDown(Enum.KeyCode.Up) or Input:IsKeyDown(Enum.KeyCode.Down)
            or Input:IsKeyDown(Enum.KeyCode.Left) or Input:IsKeyDown(Enum.KeyCode.Right)
    end
    local function runtimeReady(character)
        local scripts = me:FindFirstChild("PlayerScripts")
        local renderer = scripts and scripts:FindFirstChild("ClientRenderer")
        local controls = character:FindFirstChild("Controls")
        return adapter and adapter.character == character and renderer and renderer:IsA("LocalScript") and renderer.Enabled
            and controls and controls:IsA("LocalScript") and controls.Enabled
            and ReplicatedStorage:FindFirstChild("ClientRenderRequest") ~= nil and adapter.remote.Parent == character
    end
    local function facingStep(character, human, root, enemyRoot)
        -- 攻防/侧闪有自己的朝向目标；此处补上普通跟踪和手动操作期间的朝向。
        if not config.face or defenseBusy then return end
        if adapter and (adapter.character ~= character or adapter.selected ~= character:GetAttribute("SelectedCharacter")) then
            prepareAttack(character)
        end
        local state = runtimeReady(character) and adapter.state or nil
        rotationRecord = Facing.update(rotationRecord, character, human, root, enemyRoot, state, config.range)
    end
    local defenseStep, defenseUpdating,steerDash,flankPathClear,flankRoute,interruptMotion,evadeStep
    local function pumpDefense(deltaTime)
        if closed or not active or not config.defense or defenseUpdating then return end
        if not focused or Input:GetFocusedTextBox() or GuiService.MenuIsOpen then stop("输入或菜单打开，已暂停"); return end
        local character, human, root = parts(me)
        if not root then stop("角色死亡或重生，已暂停"); return end
        defenseUpdating = true
        local ok, reason = xpcall(defenseStep, traceback, character, human, root, deltaTime)
        defenseUpdating = false
        if not ok then fail(reason) end
    end
    local function observeSkill(other,watch,profile,at,time,seeded,speed,track)
        watch.dash=nil
        local previous=watch.skill
        watch.skill=Skill.observe(previous,profile,at,time,seeded,speed)
        if track then watch.skill.track=track end
        if watch.skill~=previous then
            watch.latest,watch.jump,watch.unknownUntil,watch.unknownId=nil,nil,nil,nil
            watch.actionAt=at;observedAttacks+=1
            pcall(trace,"SKILL_START",{player=other.UserId,name=profile.name,mode=profile.mode,phase=profile.phase,seeded=seeded or false})
        end
        pumpDefense(0)
    end
    local function syncWatchers(ownRoot)
        local keep = {}
        for _, other in ipairs(players) do
            if other ~= me then
                local character, human, root = parts(other)
                local animator = human and human:FindFirstChildOfClass("Animator")
                if root and animator and (root.Position - ownRoot.Position).Magnitude <= config.defenseRange + 18 then
                    keep[other] = true
                    local old = watchers[other]
                    if not old or old.character ~= character or old.animator ~= animator then
                        if old then old.connection:Disconnect() end
                        local watch = {character=character, animator=animator, tracks={}}
                        local function register(track, seeded)
                            if closed or not active or not config.defense then return end
                            local animation = track.Animation
                            local profile = animation and Defense.profile(animation.AnimationId)
                            local skillProfile=animation and Skill.profile(animation.AnimationId,character:GetAttribute("SelectedCharacter"))
                            local observedAt = os.clock()
                            if profile then
                                if watch.skill then watch.skill.ended=true end
                                if not profile.blockable then watch.dash=nil end
                                local record = Counter.record(profile, observedAt, track.TimePosition, seeded)
                                watch.jump=nil
                                watch.tracks[track], watch.latest, watch.unknownUntil = record, record, nil
                                watch.actionAt,watch.unknownId=observedAt,nil
                                observedAttacks += 1
                                pumpDefense(0) -- 动画事件到达即检查，不再等下一次渲染回调。
                            elseif skillProfile then
                                observeSkill(other,watch,skillProfile,observedAt,track.TimePosition,seeded,track.Speed,track)
                            elseif animation and DashGuard.side(animation.AnimationId) then
                                local dash=DashGuard.observe(watch,animation.AnimationId,observedAt,track.TimePosition,track.Speed,seeded)
                                if dash then
                                    local startVelocity=root.CFrame.RightVector*(dash.side*200.348764)
                                    dash.startX,dash.startZ=startVelocity.X,startVelocity.Z
                                    pcall(trace,"SIDE_DASH_SEEN",{player=other.UserId,side=dash.side,seeded=seeded or false})
                                    pumpDefense(0)
                                end
                            elseif animation and Jump.isAnimation(animation.AnimationId) then
                                watch.jump=Jump.observe(watch.latest,observedAt,track.TimePosition,seeded)
                                watch.actionAt=observedAt
                                pcall(trace,"JUMP_SEEN",{player=other.UserId,third=watch.jump~=nil,
                                    previousCombo=watch.latest and watch.latest.profile.combo,seeded=seeded or false})
                                pumpDefense(0)
                            elseif Counter.interruptPriority(track.Priority.Name)
                                and animation and animation.AnimationId~=character:GetAttribute("BlockAnimationId") then
                                local shot,id,position=pendingShot,animation.AnimationId,track.TimePosition
                                local kind=Contact.actionKind(shot,character,id,observedAt,position,seeded,observedAt)
                                if kind=="reaction" then
                                    pcall(trace,"HIT_REACTION",{player=other.UserId,id=id,combo=shot.combo,deferred=false})
                                elseif kind=="pending" then
                                    pcall(trace,"HIT_REACTION_PENDING",{player=other.UserId,id=id,combo=shot.combo})
                                    task.delay(.10,function()
                                        if closed or not active or not config.defense or watchers[other]~=watch
                                            or not adapter or me.Character~=adapter.character or other.Character~=character then return end
                                        local resolved=Contact.actionKind(shot,character,id,observedAt,position,seeded,os.clock())
                                        if resolved=="reaction" then
                                            pcall(trace,"HIT_REACTION",{player=other.UserId,id=id,combo=shot.combo,deferred=true})
                                        elseif Contact.markUnknown(watch,observedAt,id) then
                                            pcall(trace,"HIT_REACTION_REJECTED",{player=other.UserId,id=id})
                                            pumpDefense(0)
                                        end
                                    end)
                                elseif Contact.markUnknown(watch,observedAt,id) then pumpDefense(0) end
                            end
                            pcall(trace,"ANIMATION",{player=other.UserId,id=animation and animation.AnimationId,
                                known=profile ~= nil,time=track.TimePosition,priority=track.Priority.Name,observedAt=observedAt})
                        end
                        watch.connection = animator.AnimationPlayed:Connect(register)
                        watchers[other] = watch
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do register(track, true) end
                    end
                end
            end
        end
        for other, watch in pairs(watchers) do
            if not keep[other] then watch.connection:Disconnect(); watchers[other] = nil end
        end
    end
    defenseStep = function(ownCharacter, human, ownRoot, deltaTime)
        if not config.defense then releaseDefense(); defenseMessage = "自动防御已关闭"; return false end
        if adapter and (adapter.character ~= ownCharacter or adapter.selected ~= ownCharacter:GetAttribute("SelectedCharacter")) then
            prepareAttack(ownCharacter)
        end
        if not adapter then releaseDefense(); defenseMessage = adapterMessage; return false end
        local now, state = os.clock(), adapter.state
        local ownApproach=flankDriver.owned or evadeDriver.owned
        local manual = now < manualUntil or Input:IsKeyDown(Enum.KeyCode.F)
            or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or (state.BlockHeld and not guard.held)
        local blocked = human.Sit or human.PlatformStand or ownRoot.Anchored or ownCharacter:GetAttribute("Ragdolled")
            or state.CheckState("Freeze") or state.CheckState("Ragdoll") or state.CheckState("Rolling")
            or (state.CheckState("NoBlock") and not ownApproach and not config.evade)
            or (ownRoot:FindFirstChild("DashVelocity") ~= nil and not ownApproach) or ownRoot:FindFirstChild("RollVelocity") ~= nil
        local reason = Defense.reason({enabled=active, ready=runtimeReady(ownCharacter), manual=manual, blocked=blocked})
        if traceGate ~= (reason or "ready") then
            traceGate = reason or "ready"
            pcall(trace,"GATE",{reason=traceGate})
        end
        if reason then releaseDefense(); defenseMessage = reason; return false end
        guard:observe(ownCharacter:GetAttribute("Blocking"), now)
        watchTimer += deltaTime
        if watchTimer >= 0.05 then watchTimer = 0; syncWatchers(ownRoot) end
        local best, bestScore, bestRecord, bestPreempt, unblockable,slamThreat,skillGuard,dashGuard
        local entries = {}
        for other, watch in pairs(watchers) do
            local character, _, root = parts(other)
            if root and character == watch.character then
                local toward = ownRoot.Position - root.Position
                local distance = toward.Magnitude
                local relativeVelocity = ownRoot.AssemblyLinearVelocity - root.AssemblyLinearVelocity
                -- 远端角色可能由自定义同步移动，位置差分补足不可靠的 AssemblyLinearVelocity。
                local elapsed = watch.sampleAt and now - watch.sampleAt or 0
                if watch.offset and elapsed >= 0.002 and elapsed <= 0.25 then
                    local measured = (toward - watch.offset) / elapsed
                    local measuredClosing = distance > 0.05 and -measured:Dot(toward.Unit) or 0
                    watch.closing = math.max(math.clamp(measuredClosing, 0, 80), (watch.closing or 0) * 0.8)
                    if elapsed>=1/120 and elapsed<=.10 then
                        watch.motion={x=-measured.X,z=-measured.Z,at=now}
                    end
                end
                if not watch.sampleAt or elapsed >= 0.002 then watch.offset, watch.sampleAt = toward, now end
                local closing = math.max(watch.closing or 0, distance > 0.05 and -relativeVelocity:Dot(toward.Unit) or 0)
                local enemyUnblockable = false
                local enemyThreat, enemyRecord, enemyScore, otherAttack
                local targetState={ragdolled=character:GetAttribute("Ragdolled"),blocking=character:GetAttribute("Blocking"),
                    protected=character:GetAttribute("GodMode") or character:FindFirstChildOfClass("ForceField")~=nil}
                local disabled=Defense.targetDisabled(targetState,false)
                for track, record in pairs(watch.tracks) do
                    local age = now - record.seenAt
                    Counter.observe(record, now, track.TimePosition, track.Speed, track.IsPlaying)
                    local actual=root.CFrame:PointToObjectSpace(ownRoot.Position)
                    if config.evade and record.profile.combo==6 then
                        local danger=Slam.threat({profile=record.profile,playing=track.IsPlaying,speed=track.Speed,
                            time=track.TimePosition,age=age,disabled=Defense.targetDisabled(targetState,true),
                            visible=ray(ownRoot.Position,root.Position-ownRoot.Position,{ownCharacter,character})==nil,
                            distance=distance,x=actual.X,y=actual.Y,forward=-actual.Z})
                        if danger and not record.slamHandled and (not slamThreat or danger<slamThreat.remaining) then
                            slamThreat={player=other,character=character,root=root,record=record,track=track,remaining=danger}
                        end
                    end
                    Whiff.observe(record,{now=now,time=track.TimePosition,speed=track.Speed,playing=track.IsPlaying,
                        x=actual.X,y=actual.Y,forward=-actual.Z,damaged=lastDamageAt>=record.seenAt})
                    Interrupt.observe(record,{now=now,time=track.TimePosition,speed=track.Speed,playing=track.IsPlaying,
                        damaged=lastDamageAt>=record.seenAt})
                    if record.whiffReady and not record.whiffLogged then
                        record.whiffLogged=true
                        pcall(trace,"WHIFF_OBSERVED",{player=other.UserId,combo=record.profile.combo,samples=record.whiffSamples})
                    end
                    if age > 1.8 then watch.tracks[track] = nil
                    elseif track.IsPlaying and distance <= config.defenseRange then
                        local profile, time, speed = record.profile, track.TimePosition, track.Speed
                        local lead = math.clamp((profile.first - time) / math.max(speed, 0.01), 0, 0.18)
                        local velocity = ownRoot.AssemblyLinearVelocity - root.AssemblyLinearVelocity
                        if velocity.Magnitude > 60 then velocity = velocity.Unit * 60 end
                        local relative = root.CFrame:PointToObjectSpace(ownRoot.Position + velocity * lead)
                        local candidate = Defense.threat({profile=profile, playing=track.IsPlaying, age=age, speed=speed,
                            time=time, distance=distance, range=config.defenseRange, x=relative.X, y=relative.Y, forward=-relative.Z,
                            disabled=disabled, visible=true})
                        if candidate and ray(ownRoot.Position + Vector3.new(0, 1, 0), root.Position - ownRoot.Position,
                            {ownCharacter, character}) == nil then
                            record.wasThreat = true
                            enemyThreat = true
                            if record ~= watch.latest then otherAttack = true end
                            if not profile.blockable then unblockable, enemyUnblockable = true, true
                            else
                                local score = candidate + distance * 0.01
                                if not enemyScore or score < enemyScore then enemyScore, enemyRecord = score, record end
                            end
                        end
                    end
                end
                local flat = Vector3.new(toward.X, 0, toward.Z)
                local visible = distance <= config.defenseRange and ray(ownRoot.Position + Vector3.new(0, 1, 0),
                    root.Position - ownRoot.Position, {ownCharacter, character}) == nil
                local skillVisible=distance<=32 and ray(ownRoot.Position+Vector3.new(0,1,0),root.Position-ownRoot.Position,{ownCharacter,character})==nil
                local skillDanger=Skill.threat(watch.skill,{now=now,visible=skillVisible,ragdolled=targetState.ragdolled,
                    distance=distance,height=toward.Y})
                local dashDanger=DashGuard.threat(watch.dash,{now=now,visible=visible,
                    supported=characterNames[character:GetAttribute("SelectedCharacter")]~=nil,
                    disabled=Defense.targetDisabled(targetState,true),unblockable=enemyUnblockable,
                    distance=distance,range=config.defenseRange,height=toward.Y})
                local preempt = Defense.preempt({enabled=config.preempt or config.counter, range=config.defenseRange,
                    supported=characterNames[character:GetAttribute("SelectedCharacter")] ~= nil,
                    disabled=Defense.targetDisabled(targetState,true), unblockable=enemyUnblockable, visible=visible, distance=distance,
                    closing=closing, latency=guard.latency,
                    height=toward.Y, facing=flat.Magnitude > 0.05 and root.CFrame.LookVector:Dot(flat.Unit) or 1,
                    holding=guard.held ~= nil and defenseTarget == other})
                local travel,reachable,rearRoute,rearTravel=nil,false,nil,nil
                local facing=root.CFrame.LookVector
                local rear=Flank.behind(toward.X,toward.Z,facing.X,facing.Z,config.attackRange-.15,toward.Y)
                if Interrupt.canFlank(config.interruptStyle) and watch.latest and watch.latest.whiffReady and not disabled and visible and math.abs(toward.Y)<=3
                    and flat.Magnitude>config.attackRange and flat.Magnitude<=14 then
                    local nativeReady=ownApproach or (adapter.dashReady and (adapter.dashReady()
                        or (guard.held and adapter.dashCooldownReady())))
                    local direction=-flat.Unit
                    local gap=flat.Magnitude-config.attackRange+.3
                    if nativeReady and flankPathClear(ownRoot.Position,ownRoot.Position+direction*gap,{ownCharacter,character}) then
                        local speed=ownApproach and math.max(1,flankDriver.owned.Velocity.Magnitude) or 120
                        travel=.08+gap/speed+(guard.held and guard.releaseLatency or 0)
                        reachable=true
                    end
                end
                if Interrupt.canFlank(config.interruptStyle) and watch.latest and watch.latest.whiffReady and not disabled and visible and not rear
                    and flat.Magnitude>=2.5 and flat.Magnitude<=14 and math.abs(toward.Y)<=3
                    and (ownApproach or (adapter.dashReady and (adapter.dashReady()
                        or (guard.held and adapter.dashCooldownReady())))) then
                    local committed=counterAction and counterAction.player==other and counterAction.whiffRoute
                    rearRoute=flankRoute(ownCharacter,ownRoot,character,root,committed and committed.side)
                    if rearRoute then
                        local speed=ownApproach and math.max(1,flankDriver.owned.Velocity.Magnitude) or 200.348764
                        rearTravel=Flank.travelTime(rearRoute.length,speed)+(guard.held and guard.releaseLatency*.5 or 0)
                    end
                end
                table.insert(entries, {player=other,character=character,record=watch.latest,jump=watch.jump,
                    skill=watch.skill,skillDanger=skillDanger,dash=watch.dash,dashDanger=dashDanger,
                    distance=distance,attack=enemyThreat or skillDanger or dashDanger,otherAttack=otherAttack,
                    interruptReachable=Interrupt.advanceEligible({visible=visible,disabled=disabled or character:GetAttribute("GodMode"),
                        distance=flat.Magnitude,height=toward.Y,range=config.attackRange,limit=config.interruptRange}),
                    whiffReachable=reachable,whiffTravel=travel,
                    rear=rear,rearRoute=rearRoute,rearTravel=rearTravel,
                    attackScore=enemyScore, attackRecord=enemyRecord, preempt=preempt,
                    unknown=watch.unknownUntil and now < watch.unknownUntil and visible
                        and distance <= (config.interruptStyle=="advance" and config.interruptRange or 12),
                    unknownId=watch.unknownId,
                    feedbackEligible=not disabled and visible and distance <= 12 and math.abs(toward.Y)<=8,
                    chainVisible=visible,
                    chainEligible=not Defense.targetDisabled(targetState,true) and visible
                        and flat.Magnitude<=config.attackRange and math.abs(toward.Y)<=4,
                    landingEligible=Jump.landingGeometry({disabled=Defense.targetDisabled(targetState,true),visible=visible,
                        distance=flat.Magnitude,range=config.attackRange,height=-toward.Y}),
                    eligible=not disabled and not character:GetAttribute("GodMode") and visible
                        and flat.Magnitude <= config.attackRange and math.abs(toward.Y) <= 4})
                if skillDanger then
                    if watch.skill.profile.mode=="guard" and (not skillGuard or distance<skillGuard.distance) then
                        skillGuard=entries[#entries]
                    end
                end
            end
        end
        dashGuard=DashGuard.select(entries)
        if config.evade and evadeStep(ownCharacter,human,ownRoot,slamThreat) then defenseBusy=true;return true end
        if flankAction and (skillGuard or dashGuard) then cancelFlank(skillGuard and (skillGuard.skill.profile.name.."起手，暂停绕后") or "侧闪来袭，暂停绕后") end
        if flankAction then defenseBusy=true; return true end
        if state.CheckState("NoBlock") and not ownApproach then
            releaseDefense(); defenseMessage="自身状态暂不可格挡"; return false
        end
        local function faceThreat()
            releaseMovement(manualMovement())
            local _, _, root = parts(defenseTarget)
            if root and (config.face or not manualMovement()) and not state.CheckState("NoRotate") then
                local d = root.Position - ownRoot.Position
                local flat = Vector3.new(d.X, 0, d.Z)
                if flat.Magnitude > 0.05 then
                    local watch=watchers[defenseTarget]
                    if watch and DashGuard.active(watch.dash,now) then
                        local position,info=ReplicatedAim.read(adapter.replication,defenseTarget,watch.character,root,ownRoot,config.defenseRange)
                        if position and ray(ownRoot.Position+Vector3.new(0,1,0),position-ownRoot.Position,{ownCharacter,watch.character})~=nil then
                            position,info=nil,"occluded"
                        end
                        if position and Vector3.new(position.X-ownRoot.Position.X,0,position.Z-ownRoot.Position.Z).Magnitude>.05 then
                            flat=Vector3.new(position.X-ownRoot.Position.X,0,position.Z-ownRoot.Position.Z)
                            info.at=now
                            watch.guardAim=info
                        else
                            local fallback=type(info)=="string" and info or "overlap"
                            local relative=root.AssemblyLinearVelocity-ownRoot.AssemblyLinearVelocity
                            local vx,vz,source=DashGuard.velocity(watch.dash,now,watch.motion,{x=relative.X,z=relative.Z})
                            local x,z,lead=DashGuard.aim(flat.X,flat.Z,vx,vz)
                            flat=Vector3.new(x,0,z)
                            watch.guardAim={at=now,source=source,lead=lead,vx=vx,vz=vz,fallback=fallback}
                        end
                        local source=watch.guardAim.source
                        if watch.dash.aimSource~=source then
                            watch.dash.aimSource=source
                            pcall(trace,"SIDE_DASH_AIM",{player=defenseTarget.UserId,aim=watch.guardAim})
                        end
                    end
                    if not rotationRecord then rotationRecord = {human=human, autoRotate=human.AutoRotate} end
                    human.AutoRotate = false
                    ownRoot.CFrame = CFrame.lookAt(ownRoot.Position, ownRoot.Position + flat)
                end
            else releaseRotation() end
        end
        local combo, usedForced = Core.nextCombo(now, ownCharacter:GetAttribute("Combo"),
            ownCharacter:GetAttribute("ComboTime"), ownCharacter:GetAttribute("ForcedCombo"),
            human:GetState() == Enum.HumanoidStateType.Freefall)
        local timing = adapter.moves[combo]
        if skillGuard then
            cancelCounter(skillGuard.skill.profile.name.."起手，优先格挡")
            defenseTarget,defenseBusy=skillGuard.player,true
            Defense.engage(guard,adapter,now,function() driver:release() end,faceThreat)
            if not skillGuard.skill.guardLogged then
                skillGuard.skill.guardLogged=true
                pcall(trace,"SKILL_GUARD",{player=skillGuard.player.UserId,name=skillGuard.skill.profile.name,distance=skillGuard.distance})
            end
            defenseMessage=skillGuard.skill.profile.name.."：持续举防并跟随攻击者转向"
            return true
        end
        if dashGuard then
            cancelCounter("侧闪来袭，短暂守住并跟随转向")
            defenseTarget,defenseBusy=dashGuard.player,true
            Defense.engage(guard,adapter,now,function() driver:release() end,faceThreat)
            if not dashGuard.dash.guardLogged then
                dashGuard.dash.guardLogged=true
                pcall(trace,"SIDE_DASH_GUARD",{player=dashGuard.player.UserId,side=dashGuard.dash.side,distance=dashGuard.distance})
            end
            defenseMessage="侧闪来袭：短暂保持格挡并提前转向"
            return true
        end
        if blockFeedback then
            local matched = Gap.feedback(entries,blockFeedback.at,now)
            if matched then
                pcall(trace,"BLOCK_MATCH",{player=matched.player.UserId,combo=matched.record.profile.combo,
                    hits=matched.record.blockedHits,ready=matched.record.gapReady})
                local fits,deadline,budget=Gap.window(matched.record,now,guard.releaseLatency,timing)
                pcall(trace,"GAP_WINDOW",{player=matched.player.UserId,combo=matched.record.profile.combo,fits=fits,
                    remaining=deadline and deadline-now,budget=budget,eligible=matched.eligible})
                blockFeedback=nil
            elseif now-blockFeedback.at>.12 then blockFeedback=nil end
        end
        for _, entry in ipairs(entries) do
            local record = entry.record
            local front=Interrupt.frontOnly(config.interruptStyle)
            local advance=config.interruptStyle=="advance"
            if config.jump and config.counter and entry.jump then
                local ready=Jump.window(entry.jump,record,now,timing,lastDamageAt)
                if ready and advance and entry.interruptReachable and not entry.unknown
                    and adapter.dashReady and (adapter.dashReady() or (guard.held and adapter.dashCooldownReady())) then
                    local c,_,r=parts(entry.player)
                    local delta=r and r.Position-ownRoot.Position
                    local flat=delta and Vector3.new(delta.X,0,delta.Z)
                    local length=flat and flat.Magnitude-Interrupt.advanceStop(config.attackRange)
                    if length and length>0 and flankPathClear(ownRoot.Position,ownRoot.Position+flat.Unit*length,{ownCharacter,c}) then
                        entry.jumpRoute={kind="advance",direction=flat.Unit,length=length,side=1}
                        entry.jumpTravel=Flank.travelTime(length)
                    end
                end
                if not entry.jump.logged then
                    entry.jump.logged=true
                    pcall(trace,"JUMP_WINDOW",{player=entry.player.UserId,ready=ready,distance=entry.distance,
                        near=entry.eligible,route=entry.jumpRoute~=nil,sinceJump=now-entry.jump.at,
                        thirdComplete=record and (record.gapReady or record.finished or record.interruptReady) or false})
                end
            end
            local eligible=advance and entry.interruptReachable or (not advance and entry.eligible)
            if config.interrupt and config.gap and config.counter and combo<=3 and eligible and (front or advance or not entry.rear)
                and record and (record.gapReady or record.interruptReady or (advance and record.whiffReady))
                and (not counterAction or counterAction.phase=="release")
                and not entry.unknown and not entry.otherAttack and (front or entry.distance>=2.5)
                and Contact.canStart(pendingShot,combo,now,entry.character)
                and (front or (adapter.dashReady and (adapter.dashReady() or (guard.held and adapter.dashCooldownReady())))) then
                if not front then
                    local c,_,r=parts(entry.player)
                    local route
                    if r and advance then
                        local delta=r.Position-ownRoot.Position
                        local flat=Vector3.new(delta.X,0,delta.Z)
                        local length=flat.Magnitude-Interrupt.advanceStop(config.attackRange)
                        if length>0 and flankPathClear(ownRoot.Position,ownRoot.Position+flat.Unit*length,{ownCharacter,c}) then
                            route={kind="advance",direction=flat.Unit,length=length,side=1}
                        end
                    elseif r then route=flankRoute(ownCharacter,ownRoot,c,r,nil,true) end
                    entry.interruptRoute=route
                    entry.interruptTravel=route and Flank.travelTime(route.length)
                end
                if front or entry.interruptRoute then
                    local fits,deadline,source,budget=Interrupt.window(record,now,guard.releaseLatency,timing,entry.interruptTravel,lastDamageAt,config.interruptStyle)
                    if not record.interruptLogged or (fits and not record.interruptFitLogged) then
                        record.interruptLogged,record.interruptFitLogged=true,fits or record.interruptFitLogged
                        pcall(trace,"INTERRUPT_WINDOW",{player=entry.player.UserId,combo=record.profile.combo,source=source,
                            style=config.interruptStyle,distance=entry.distance,fits=fits,budget=budget,travel=entry.interruptTravel,remaining=deadline and deadline-now})
                    end
                end
            end
            if config.gap and Interrupt.canFlank(config.interruptStyle) then
                local committedRear=counterAction and counterAction.player==entry.player and counterAction.whiffRoute and not entry.rear
                Whiff.plan(entry,now,guard.releaseLatency,timing,lastDamageAt,committedRear)
            end
            if config.counter and record and record.finished and record.wasThreat and not record.windowLogged then
                record.windowLogged = true
                local fits, deadline, budget = Counter.window(record, now, guard.latency, timing,
                    guard.held ~= nil or ownCharacter:GetAttribute("Blocking"))
                pcall(trace,"COUNTER_WINDOW",{player=entry.player.UserId,enemyCombo=record.profile.combo,
                    fits=fits,remaining=deadline and deadline-now,budget=budget,distance=entry.distance,eligible=entry.eligible})
            end
            if config.gap and record and record.whiffReady and not record.whiffWindowLogged then
                record.whiffWindowLogged=true
                local fits,deadline,budget=Whiff.window(record,now,guard.releaseLatency,timing,lastDamageAt,entry.whiffTravel)
                pcall(trace,"WHIFF_WINDOW",{player=entry.player.UserId,combo=record.profile.combo,fits=fits,
                    distance=entry.distance,eligible=entry.eligible,reachable=entry.whiffReachable,travel=entry.whiffTravel,
                    approach=entry.whiffRoute and "rear" or "direct",
                    remaining=deadline and deadline-now,budget=budget})
            end
        end
        if counterAction and counterAction.weaving then
            local selected,otherThreat
            for _,e in ipairs(entries) do
                if e.player==counterAction.player then selected=e
                elseif e.attack or e.preempt or e.unknown then otherThreat=true end
            end
            local motion=interruptMotion(ownCharacter,human,ownRoot,selected,otherThreat,false)
            if motion=="abort" then cancelCounter("抢断侧闪未到位或条件改变，恢复防御")
            elseif motion=="move" then
                defenseTarget,defenseBusy=counterAction.player,true
                counterMessage=counterAction.interruptStyle=="advance" and "出拳前摇中直线侧闪，接近后刹停" or "出拳前摇中侧闪，抢入侧后方"
                defenseMessage=counterMessage
                return true
            end
        end
        local counterEntry
        if counterAction and counterAction.phase == "struck" then
            local interrupted = not config.counter or manualMovement()
            for _, entry in ipairs(entries) do
                if entry.player == counterAction.player then
                    counterEntry = entry
                    counterAction.lastEntryStatus={visible=entry.chainVisible,eligible=entry.chainEligible,
                        landingEligible=entry.landingEligible,landingWait=Jump.waitForLanding(counterAction,entry,now) or false,
                        sameCharacter=counterAction.shot and counterAction.shot.target==entry.character,
                        unknown=entry.unknown or false,unknownId=entry.unknownId,changed=entry.record~=counterAction.record,
                        attack=entry.attack or false,otherAttack=entry.otherAttack or false}
                    if Contact.targetInterrupted({pressure=Contact.pressure(counterAction.shot,counterAction.previousHitAt,now)
                        or (counterAction.interruptOpportunity and Contact.pending(counterAction.shot,now)),
                        changed=entry.record~=counterAction.record,
                        unknown=entry.unknown or (entry.skillDanger and entry.skill~=counterAction.record),otherAttack=entry.otherAttack,
                        attack=entry.attack and not counterAction.gapOpportunity}) then interrupted=true end
                elseif entry.attack or entry.preempt or entry.unknown then interrupted = true end
            end
            if not counterEntry or interrupted or lastDamageAt>=counterAction.startedAt then
                cancelCounter("出现新威胁或受击，恢复防御"); counterEntry = nil
            elseif now >= counterAction.recoverAt or not state.CheckState("NoM1") then
                local landing=Jump.waitForLanding(counterAction,counterEntry,now)
                local reason=Counter.chainReason(counterAction,{enabled=config.chain,now=now,eligible=counterEntry.chainEligible or landing})
                if not reason and counterAction.shot and now>counterAction.shot.deadline
                    and not Contact.canContinue(counterAction.shot,now) then reason="未确认命中，恢复防御" end
                if reason then cancelCounter(reason); counterEntry=nil end
                if counterAction and landing and counterAction.landingShot~=counterAction.shot then
                    counterAction.landingShot=counterAction.shot
                    pcall(trace,"JUMP_LAND_WAIT",{player=counterAction.player.UserId,combo=counterAction.lastCombo})
                elseif counterAction and counterEntry.chainEligible and counterAction.landingShot==counterAction.shot then
                    counterAction.landingShot=nil
                    pcall(trace,"JUMP_LAND_READY",{player=counterAction.player.UserId,combo=counterAction.lastCombo})
                end
            end
        else
            if config.counter and combo<=3 and not manualMovement() and not state.CheckState("NoRotate")
                and now >= driver.nextAt and (guard.held or counterAction or not state.CheckState("NoM1")) then
                local releaseWait = guard.held ~= nil or ownCharacter:GetAttribute("Blocking")
                if counterAction and releaseWait then
                    releaseWait = math.max(0, guard.latency - (now - counterAction.releaseAt))
                end
                local preferred = counterAction and counterAction.player
                if not counterAction or counterAction.skillOpportunity then
                    counterEntry=Skill.select(entries,now,guard.releaseLatency,timing,lastDamageAt,preferred)
                    if counterEntry then
                        counterEntry.record=counterEntry.skill
                        counterEntry.skillOpportunity=true;counterEntry.gapOpportunity=true;counterEntry.interruptOpportunity=true
                        counterEntry.interruptStyle="front"
                        local fits,remaining,budget=Skill.window(counterEntry.record,now,guard.releaseLatency,timing,lastDamageAt)
                        if not counterEntry.record.windowLogged then
                            counterEntry.record.windowLogged=true
                            pcall(trace,"SKILL_WINDOW",{name=counterEntry.record.profile.name,remaining=remaining,budget=budget,fits=fits})
                        end
                    end
                end
                if not counterEntry and config.jump and (not counterAction or counterAction.jumpOpportunity) then
                    counterEntry=Jump.select(entries,now,timing,lastDamageAt,preferred)
                    if counterEntry then
                        counterEntry.gapOpportunity=true; counterEntry.interruptOpportunity=true; counterEntry.jumpOpportunity=true
                    end
                end
                if not counterEntry and config.interrupt and config.gap and (not counterAction or counterAction.interruptOpportunity)
                    and not (counterAction and (counterAction.jumpOpportunity or counterAction.skillOpportunity)) then
                    counterEntry=Interrupt.select(entries,now,guard.releaseLatency,timing,lastDamageAt,preferred,config.interruptStyle)
                    if counterEntry then counterEntry.gapOpportunity=true; counterEntry.interruptOpportunity=true end
                end
                if not counterEntry and config.gap and (not counterAction or counterAction.gapOpportunity)
                    and not (counterAction and (counterAction.whiffOpportunity or counterAction.interruptOpportunity)) then
                    counterEntry=Gap.select(entries,now,guard.releaseLatency,timing,preferred)
                    if counterEntry then counterEntry.gapOpportunity=true end
                end
                if config.gap and not counterEntry and not blockFeedback and (not counterAction or counterAction.whiffOpportunity) then
                    counterEntry=Whiff.select(entries,now,guard.releaseLatency,timing,lastDamageAt,preferred)
                    if counterEntry then counterEntry.gapOpportunity=true; counterEntry.whiffOpportunity=true end
                end
                if not counterEntry and not (counterAction and counterAction.gapOpportunity) then
                    counterEntry = Counter.select(entries, now, guard.latency, timing, releaseWait, preferred)
                end
            end
            if counterEntry and not Contact.canStart(pendingShot,combo,now,counterEntry.character) then counterEntry=nil end
            if counterAction and (not counterEntry or counterEntry.record ~= counterAction.record) then
                cancelCounter("反击条件改变，恢复防御"); counterEntry = nil
            end
            if counterEntry and not counterAction then
                pcall(trace,"COUNTER_OPEN",{player=counterEntry.player.UserId,enemyCombo=counterEntry.record.profile.combo,
                    style=counterEntry.interruptStyle or config.interruptStyle,
                    mode=counterEntry.skillOpportunity and "skill" or (counterEntry.jumpOpportunity and "jump" or (counterEntry.interruptOpportunity and "interrupt" or (counterEntry.whiffOpportunity and "whiff" or (counterEntry.gapOpportunity and "gap" or "recovery"))))})
                local fastRelease=counterEntry.gapOpportunity and guard.held~=nil
                counterAction = Counter.begin(counterEntry, now, guard, driver)
                counterAction.gapOpportunity,counterAction.fastRelease=counterEntry.gapOpportunity,fastRelease
                counterAction.whiffOpportunity=counterEntry.whiffOpportunity
                counterAction.whiffRoute=counterEntry.whiffRoute
                counterAction.interruptOpportunity=counterEntry.interruptOpportunity
                counterAction.interruptRoute,counterAction.interruptDeadline=counterEntry.interruptRoute,counterEntry.interruptDeadline
                counterAction.interruptSource=counterEntry.interruptSource
                counterAction.interruptStyle=counterEntry.interruptStyle
                counterAction.jumpOpportunity,counterAction.jump=counterEntry.jumpOpportunity,counterEntry.jump
                counterAction.skillOpportunity=counterEntry.skillOpportunity
            end
        end
        if counterAction and counterEntry then
            defenseTarget, defenseBusy = counterAction.player, true
            faceThreat()
            local enemyCharacter, _, root = parts(counterAction.player)
            local flat = root and root.Position - ownRoot.Position or Vector3.zero
            flat = Vector3.new(flat.X, 0, flat.Z)
            if counterAction.whiffOpportunity and counterAction.phase=="release"
                and (counterAction.approachDash or counterAction.whiffRoute or not counterEntry.eligible) then
                if not Interrupt.canFlank(config.interruptStyle) then cancelCounter("当前测试不使用空招绕后接近，恢复防御"); return false end
                local route=counterAction.whiffRoute
                local arrived=flat.Magnitude<=config.attackRange-.15 and (not route or counterEntry.rear)
                if arrived then
                    flankDriver:release(true)
                    counterAction.approachDash=false
                    faceThreat()
                    pcall(trace,"WHIFF_ARRIVE",{distance=flat.Magnitude,approach=route and "rear" or "direct",rear=counterEntry.rear})
                else
                    if not counterEntry.whiffReachable and not counterEntry.eligible then
                        cancelCounter("空招接近路线或冷却不可用"); return false
                    end
                    local direction=flat.Unit
                    if route then
                        local x,z=Flank.steer(-flat.X,-flat.Z,route.radius,route.side)
                        if not x then cancelCounter("绕后方向不可用"); return false end
                        direction=Vector3.new(x,0,z)
                    end
                    local side=route and route.side or 1
                    local look=Vector3.new(direction.Z*side,0,-direction.X*side)
                    if not steerDash(ownCharacter,human,ownRoot,look) then cancelCounter("空招接近镜头不可用"); return false end
                    if not counterAction.approachDash then
                        if state.BlockHeld or state.CheckState("NoDash") then
                            counterMessage="等待松防，准备抓空招"; return true
                        end
                        if not flankDriver:launch(adapter,ownRoot,side) then cancelCounter("空招接近侧闪尚未就绪"); return false end
                        counterAction.approachDash=true
                        pcall(trace,"WHIFF_APPROACH",{distance=flat.Magnitude,travel=counterEntry.whiffTravel,approach=route and "rear" or "direct"})
                    end
                    local velocity=flankDriver.owned
                    if not velocity or velocity.Parent~=ownRoot then cancelCounter("侧闪结束，未进入出拳距离"); return false end
                    local probe=math.min(flat.Magnitude,math.max(1.5,velocity.Velocity.Magnitude*.04))
                    if not flankPathClear(ownRoot.Position,ownRoot.Position+direction*probe,{ownCharacter,enemyCharacter}) then
                        cancelCounter("空招接近遇到障碍或落差"); return false
                    end
                    velocity.Velocity=direction*velocity.Velocity.Magnitude
                    counterMessage=route and "抓空招：优先侧闪绕后" or "抓空招：短侧闪接近"
                    defenseMessage=counterMessage
                    return true
                end
            end
            -- FUp 和后续 M1 通过同一个 Network 依次发送。沿用原 Controls 的本地
            -- BlockHeld/NoM1 判定，仅在刚松开自己持有的格挡后容忍旧 Blocking 属性。
            local fastRelease=counterAction.fastRelease and now-counterAction.releaseAt<.45
            local gates={valid=true,manual=manual or manualMovement(),
                blocking=not fastRelease and ownCharacter:GetAttribute("Blocking"),blockHeld=state.BlockHeld,
                blocked=combatBlocked(ownCharacter,human,ownRoot,fastRelease),
                cooldown=state.CheckState("NoM1") or now<driver.nextAt,
                facing=flat.Magnitude>.05 and ownRoot.CFrame.LookVector:Dot(flat.Unit) or 1}
            local fired, reason
            driver.targetCharacter=enemyCharacter
            if counterAction.phase == "release" then
                if counterAction.interruptStyle=="advance" then counterAction.interruptRoute=counterEntry.interruptRoute end
                fired,reason=Counter.commit(counterAction,driver,adapter,ownCharacter,combo,now,gates)
                counterMessage=reason or (counterAction.whiffOpportunity and "空招抢攻：发起第一拳" or "挡中抢攻：发起第一拳")
            elseif config.chain and not Counter.chainReason(counterAction,{enabled=true,now=now,eligible=counterEntry.chainEligible})
                and Contact.canContinue(counterAction.shot,now) then
                fired=Counter.chain(counterAction,driver,adapter,ownCharacter,combo,now,gates)
                counterMessage="反击连击中：第 "..tostring(counterAction.punches).." 拳"
            elseif config.chain and Jump.waitForLanding(counterAction,counterEntry,now) then
                counterMessage="起跳抢断已命中，等待落回出拳高度"
            else counterMessage=Contact.chainReason(counterAction.shot,now) or "反击收招，准备恢复防御" end
            if fired then
                if usedForced then ownCharacter:SetAttribute("ForcedCombo",nil) end
                counterCount += 1
                pcall(trace,"COUNTER_STRIKE",{player=counterAction.player.UserId,combo=combo,punch=counterAction.punches,
                    style=counterAction.interruptStyle or config.interruptStyle,
                    mode=counterAction.skillOpportunity and "skill" or (counterAction.jumpOpportunity and "jump" or (counterAction.interruptOpportunity and "interrupt" or (counterAction.whiffOpportunity and "whiff" or (counterAction.gapOpportunity and "gap" or "recovery")))),enemyCombo=counterAction.record.profile.combo,
                    sinceJump=counterAction.jump and now-counterAction.jump.at,
                    sinceBlock=counterAction.record.blockedAt and now-counterAction.record.blockedAt,
                    sinceLastHit=now-counterAction.record.startedAt-counterAction.record.profile.last})
                if counterAction.interruptOpportunity and counterAction.punches==1
                    and not Interrupt.frontOnly(counterAction.interruptStyle) then
                    local motion=interruptMotion(ownCharacter,human,ownRoot,counterEntry,false,true)
                    if motion=="abort" then cancelCounter("原侧闪未能执行，恢复防御"); return false end
                    counterMessage=counterAction.interruptStyle=="advance" and "直进抢断：出拳同时侧闪接近" or "间隙抢断：出拳同时侧闪绕后"
                elseif counterAction.interruptOpportunity and counterAction.punches==1 then
                    counterMessage=counterAction.skillOpportunity and "闪电光芒起手：近身抢断，命中后接三段"
                        or (counterAction.jumpOpportunity and "第三段后起跳：提前出拳抢断" or "正面抢断：出拳，等待命中接三段")
                end
            end
            defenseMessage = counterMessage
            return true
        end
        for _, entry in ipairs(entries) do
            local score = entry.attackScore
            if score and (not best or score < bestScore) then
                best, bestScore, bestRecord, bestPreempt = entry.player, score, entry.attackRecord, false
            end
            score = 10 + entry.distance * 0.01
            if config.preempt and entry.preempt and (not best or score < bestScore) then
                best, bestScore, bestRecord, bestPreempt = entry.player, score, nil, true
            end
        end
        if best then
            -- 先松开脚本拥有的普攻输入，再发格挡；不取消游戏中已经打出的那一拳。
            defenseTarget = best
            local wasHeld = guard.held ~= nil
            Defense.engage(guard, adapter, now, function() driver:release() end, faceThreat)
            if not wasHeld then
                if bestPreempt then preemptCount += 1; lastDefenseDelay = nil
                else lastDefenseDelay = math.max(0, os.clock() - bestRecord.seenAt) * 1000 end
            end
            defenseMessage = bestPreempt and ("提前举防：" .. best.DisplayName .. " 近身朝向你")
                or ("检测到 " .. best.DisplayName .. " 的普攻")
        elseif not guard:expire(now) then
            defenseTarget = nil
            defenseMessage = unblockable and "检测到下砸：无法格挡"
                or (config.preempt and "监测近身威胁、普攻与指定技能" or "监测附近玩家的普攻与指定技能")
        else defenseMessage = "短暂保持格挡，等待攻击结束" end
        defenseBusy = best ~= nil or guard.held ~= nil
        if defenseBusy then
            driver:release()
            if not best then faceThreat() end
        elseif not config.attack then releaseRotation() end
        return defenseBusy
    end
    local function flankThreat(ownCharacter,ownRoot,chosen,pressure)
        for _,other in ipairs(players) do
            if other~=me then
                local c,h,r=parts(other)
                if r and (r.Position-ownRoot.Position).Magnitude<=18 and not c:GetAttribute("Ragdolled") then
                    local offset=r.CFrame:PointToObjectSpace(ownRoot.Position)
                    local distance=(r.Position-ownRoot.Position).Magnitude
                    local visible=ray(ownRoot.Position,r.Position-ownRoot.Position,{ownCharacter,c})==nil
                    if visible then
                        if other~=chosen and not c:GetAttribute("Blocking") and distance<10
                            and -offset.Z>distance*.45 and math.abs(offset.Y)<5 then return true end
                        local animator=h:FindFirstChildOfClass("Animator")
                        if animator then
                            for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                                local animation=track.Animation
                                local profile=animation and Defense.profile(animation.AnimationId)
                                if profile and not (other==chosen and pressure) and Defense.threat({profile=profile,playing=track.IsPlaying,age=0,
                                    speed=track.Speed,time=track.TimePosition,distance=distance,range=18,visible=true,
                                    x=offset.X,y=offset.Y,forward=-offset.Z}) then return true end
                                if animation and not profile and Counter.interruptPriority(track.Priority.Name)
                                    and animation.AnimationId~=c:GetAttribute("BlockAnimationId")
                                    and not c:GetAttribute("Blocking") and distance<10 and -offset.Z>0 then return true end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    flankPathClear=function(from,to,exclude)
        local delta=to-from
        local flat=Vector3.new(delta.X,0,delta.Z)
        local side=flat.Magnitude>.01 and Vector3.new(-flat.Z,0,flat.X).Unit*1.25 or Vector3.zero
        for _,offset in ipairs({Vector3.zero,side,-side}) do
            if ray(from+offset,delta,exclude) then return false end
            local floor=ray(to+offset+Vector3.new(0,2,0),Vector3.new(0,-8,0),exclude)
            if not floor or floor.Normal.Y<.65 or to.Y-floor.Position.Y>5.5 or to.Y-floor.Position.Y<1 then return false end
        end
        return true
    end
    flankRoute=function(ownCharacter,ownRoot,enemyCharacter,enemyRoot,forcedSide,earlyRear)
        local d=ownRoot.Position-enemyRoot.Position
        local maximum=math.min(6,config.attackRange-.3)
        local radius=math.clamp(Vector3.new(d.X,0,d.Z).Magnitude,math.min(4.5,maximum),maximum)
        local facing=enemyRoot.CFrame.LookVector
        local routes={}
        for _,side in ipairs({1,-1}) do
            local route=Flank.arc(d.X,d.Z,facing.X,facing.Z,radius,side)
            local previous=ownRoot.Position
            route.clear,route.length=true,0
            for index,point in ipairs(route.points) do
                local nextPoint=Vector3.new(enemyRoot.Position.X+point.x,ownRoot.Position.Y,enemyRoot.Position.Z+point.z)
                if not flankPathClear(previous,nextPoint,{ownCharacter,enemyCharacter}) then route.clear=false; break end
                route.length+=(nextPoint-previous).Magnitude
                previous=nextPoint
                if earlyRear then
                    local behind,dot=Flank.behind(point.x,point.z,facing.X,facing.Z,config.attackRange-.15,0)
                    if behind and dot<=-.65 then route.angle=route.angle*index/#route.points; break end
                end
            end
            route.radius=radius
            table.insert(routes,route)
        end
        if forcedSide then local route=routes[forcedSide==1 and 1 or 2]; return route.clear and route or nil end
        return Flank.chooseRoute(routes[1],routes[2])
    end
    steerDash=function(character,human,root,look)
        local camera=Workspace.CurrentCamera
        if not camera then return false end
        if cameraRecord and cameraRecord.camera~=camera then return false end
        if not cameraRecord then
            local offset=camera.CFrame.Position-root.Position
            cameraRecord={camera=camera,kind=camera.CameraType,subject=camera.CameraSubject,
                distance=math.clamp(Vector3.new(offset.X,0,offset.Z).Magnitude,8,24),height=math.clamp(offset.Y,4,10)}
            camera.CameraType=Enum.CameraType.Scriptable
        elseif camera.CameraType~=Enum.CameraType.Scriptable then return false end
        if not rotationRecord then rotationRecord={human=human,autoRotate=human.AutoRotate} end
        human.AutoRotate=false
        root.CFrame=CFrame.lookAt(root.Position,root.Position+look)
        local anchor=root.Position+Vector3.new(0,1.5,0)
        local desired=root.Position-look*cameraRecord.distance+Vector3.new(0,cameraRecord.height,0)
        local obstacle=ray(anchor,desired-anchor,{character})
        if obstacle then desired=obstacle.Position+obstacle.Normal*.6 end
        -- 原 Dash 每帧读取镜头水平朝向。相机只改变朝向，侧闪速度沿用原 Tween。
        camera.CFrame=CFrame.lookAt(desired,desired+look*12+Vector3.new(0,-cameraRecord.height,0))
        camera.Focus=CFrame.new(anchor)
        return true
    end
    evadeStep=function(ownCharacter,human,ownRoot,threat)
        local now,state=os.clock(),adapter.state
        local manual=manualMovement() or now<manualUntil or Input:IsKeyDown(Enum.KeyCode.F)
            or Input:IsKeyDown(Enum.KeyCode.Q) or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if manual then if evadeAction then cancelEvade("手动操作优先") end; return false end
        if not evadeAction and threat then
            local a={player=threat.player,character=threat.character,record=threat.record,track=threat.track,
                startedAt=now,phase="prepare"}
            -- 攻击侧闪已经启动时只转交其速度对象；不会在冷却中再次发动侧闪。
            local reused=evadeDriver:takeFrom(flankDriver)
            cancelCounter("识别到下砸，暂停反击")
            cancelFlank("识别到下砸，暂停绕后")
            if pendingShot then pendingShot.cancelled=true end
            driver:release()
            evadeAction=a; a.record.slamHandled=true; a.record.wasThreat=true
            evadeCount+=1
            pcall(trace,"SLAM_OPEN",{player=a.player.UserId,remaining=threat.remaining,reused=reused,
                distance=(ownRoot.Position-threat.root.Position).Magnitude})
        end
        local a=evadeAction
        if not a then return false end
        local c,_,r=parts(a.player)
        local d=r and ownRoot.Position-r.Position or Vector3.zero
        local flat=Vector3.new(d.X,0,d.Z)
        if not a.route and r then
            local routes=Slam.routes(d.X,d.Z)
            for _,route in ipairs(routes) do
                local direction=Vector3.new(route.x,0,route.z)
                local previous=ownRoot.Position
                route.clear=true
                for i=1,math.ceil(route.length/2) do
                    local nextPoint=ownRoot.Position+direction*math.min(route.length,i*2)
                    if not flankPathClear(previous,nextPoint,{ownCharacter,c}) then route.clear=false; break end
                    previous=nextPoint
                end
            end
            a.route=Slam.choose(routes)
            if a.route then
                local remaining=(a.record.profile.first-a.track.TimePosition)/math.max(a.track.Speed,.01)
                local travel=Flank.travelTime(a.route.length)
                local fits,budget=Slam.window(remaining,travel,guard.releaseLatency,guard.held~=nil)
                pcall(trace,"SLAM_ROUTE",{length=a.route.length,travel=travel,remaining=remaining,budget=budget,fits=fits})
            end
        end
        local route=a.route
        local direction=route and Vector3.new(route.x,0,route.z)
        local velocity=evadeDriver.owned
        local speed=velocity and velocity.Parent==ownRoot and velocity.Velocity.Magnitude or human.WalkSpeed
        local path=direction and flankPathClear(ownRoot.Position,ownRoot.Position+direction*math.clamp(speed*.035,1.5,4),{ownCharacter,c})
        local motion=Slam.motion({now=now,elapsed=now-a.startedAt,manual=manual,damaged=lastDamageAt>=a.startedAt,
            blocked=state.CheckState("Freeze") or state.CheckState("Ragdoll") or state.CheckState("Rolling")
                or state.CheckState("NoRotate") or human.Sit or human.PlatformStand,
            alive=r~=nil and c==a.character,playing=a.track.IsPlaying,time=a.track.TimePosition,last=a.record.profile.last,
            distance=flat.Magnitude,path=path})
        if motion=="abort" or motion=="done" then
            cancelEvade(motion=="done" and "下砸打击阶段结束，恢复原攻防" or "受击、状态改变或避让超时",motion=="done")
            return false
        end
        defenseTarget,defenseBusy=a.player,true
        if motion=="hold" then
            evadeDriver:release(true); releaseMovement(false)
            if a.phase~="hold" then pcall(trace,"SLAM_CLEAR",{distance=flat.Magnitude,elapsed=now-a.startedAt}) end
            a.phase="hold"
            if flat.Magnitude>.05 then steerDash(ownCharacter,human,ownRoot,-flat.Unit) end
            defenseMessage="已拉开下砸范围，等待打击结束"
            return true
        end
        if motion=="wait" then
            evadeDriver:release(); releaseMovement(false)
            if a.phase~="wait" then pcall(trace,"SLAM_WAIT",{reason="没有可通行的退避路线"}) end
            a.phase="wait"; a.route=nil
            defenseMessage="下砸无法格挡，退避路线受阻"
            return true
        end
        guard:release()
        releaseMovement(false)
        local look=Vector3.new(direction.Z,0,-direction.X)
        if not steerDash(ownCharacter,human,ownRoot,look) then cancelEvade("避让方向或镜头不可用"); return false end
        if not evadeDriver.owned and not a.dashAttempted and adapter.dashReady and adapter.dashReady() then
            a.dashAttempted=true
            if evadeDriver:launch(adapter,ownRoot,1) then pcall(trace,"SLAM_DASH",{distance=flat.Magnitude}) end
        end
        velocity=evadeDriver.owned
        if velocity and velocity.Parent==ownRoot then
            a.phase="dash"; velocity.Velocity=direction*velocity.Velocity.Magnitude
            defenseMessage="下砸避让：原侧闪拉开距离"
        else
            if a.phase~="walk" then pcall(trace,"SLAM_WALK",{distance=flat.Magnitude,noDash=state.CheckState("NoDash")}) end
            a.phase="walk"
            if not state.CheckState("NoMovement") then human:Move(direction,false); movingHuman=human end
            defenseMessage="下砸避让：侧闪未就绪，普通移动退开"
        end
        return true
    end
    interruptMotion=function(ownCharacter,human,ownRoot,entry,otherThreat,launch)
        if Interrupt.frontOnly(config.interruptStyle) then return "abort" end
        local a=counterAction
        if not a or not a.interruptRoute then return "abort" end
        local c,_,r=parts(a.player)
        local now=os.clock()
        local d=r and ownRoot.Position-r.Position or Vector3.zero
        local flat=Vector3.new(d.X,0,d.Z)
        local rear,dot=false,nil
        if r then local f=r.CFrame.LookVector; rear,dot=Flank.behind(d.X,d.Z,f.X,f.Z,config.attackRange-.15,d.Y) end
        local route=a.interruptRoute
        local advance=a.interruptStyle=="advance"
        local direction,x,z,forward,lateral
        if advance then
            direction=route.direction
            x,z=direction.X,direction.Z
            forward,lateral=-flat:Dot(direction),d.X*direction.Z-d.Z*direction.X
        else
            x,z=Flank.steer(d.X,d.Z,route.radius,route.side)
            direction=x and Vector3.new(x,0,z)
        end
        local state=adapter.state
        local velocity=flankDriver.owned
        local speed=velocity and velocity.Parent==ownRoot and velocity.Velocity.Magnitude or 200.348764
        local path=direction and flankPathClear(ownRoot.Position,ownRoot.Position+direction*math.clamp(speed*.035,1.5,4),{ownCharacter,c})
        if launch then
            local timing=adapter.moves[a.lastCombo]
            local hit=type(timing.HitTime)=="table" and timing.HitTime[1] or timing.HitTime
            a.weaveDeadline=math.min(a.shot.sentAt+hit-.035,a.interruptDeadline)
        end
        local motion=Interrupt.motion({style=a.interruptStyle,startRange=config.interruptRange,forward=forward,lateral=lateral,
            now=now,deadline=a.weaveDeadline,manual=manualMovement() or now<manualUntil,
            damaged=lastDamageAt>=a.startedAt,blocked=state.CheckState("Freeze") or state.CheckState("Ragdoll")
                or state.CheckState("Rolling") or state.CheckState("NoRotate"),
            alive=r~=nil and c==a.shot.target,protected=c and (c:GetAttribute("GodMode") or c:GetAttribute("Ragdolled")
                or c:FindFirstChildOfClass("ForceField")),visible=entry and entry.chainVisible,
            otherThreat=otherThreat,unknown=entry and entry.unknown,distance=flat.Magnitude,height=d.Y,
            range=config.attackRange,rear=rear,path=path,velocity=launch or (velocity and velocity.Parent==ownRoot)})
        if motion=="abort" then
            pcall(trace,"INTERRUPT_ABORT",{style=a.interruptStyle,distance=flat.Magnitude,dot=dot,
                forward=forward,lateral=lateral,remaining=a.weaveDeadline-now,path=path})
            return motion
        end
        if motion=="arrive" then
            flankDriver:release(true); a.weaving=false
            if flat.Magnitude>.05 and not steerDash(ownCharacter,human,ownRoot,-flat.Unit) then return "abort" end
            pcall(trace,"INTERRUPT_ARRIVE",{style=a.interruptStyle,distance=flat.Magnitude,dot=dot,
                forward=forward,lateral=lateral,elapsed=now-a.shot.sentAt})
            return motion
        end
        local look=Vector3.new(z*route.side,0,-x*route.side)
        if not steerDash(ownCharacter,human,ownRoot,look) then return "abort" end
        if launch then
            if not flankDriver:launch(adapter,ownRoot,route.side) then return "abort" end
            a.weaving=true; interruptCount+=1
            pcall(trace,"INTERRUPT_DASH",{style=a.interruptStyle,side=route.side,source=a.interruptSource,remaining=a.weaveDeadline-now,
                distance=flat.Magnitude,shotAge=now-a.shot.sentAt})
        end
        velocity=flankDriver.owned
        if not velocity or velocity.Parent~=ownRoot then return "abort" end
        velocity.Velocity=direction*velocity.Velocity.Magnitude
        return "move"
    end
    local function flankStep(ownCharacter,human,ownRoot)
        if evadeAction then return false end
        if not Interrupt.canFlank(config.interruptStyle) then
            if flankAction then cancelFlank("当前抢断测试停用独立侧闪与绕后") end
            dashRequested=false
            return false
        end
        local now=os.clock()
        local manual=now<manualUntil or manualMovement() or Input:IsKeyDown(Enum.KeyCode.F)
            or Input:IsKeyDown(Enum.KeyCode.Q) or Input:IsKeyDown(Enum.KeyCode.Space)
            or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        if adapter and (adapter.character~=ownCharacter or adapter.selected~=ownCharacter:GetAttribute("SelectedCharacter")) then
            prepareAttack(ownCharacter); return false
        end
        if not flankAction then
            if not dashRequested and not config.flank then return false end
            if not adapter then
                if not loading then prepareAttack(ownCharacter) end
                flankMessage=adapterMessage; return false
            end
            if not adapter.dash then flankMessage="侧闪接口不可用："..tostring(adapter.dashError); dashRequested=false; return false end
            if counterAction or now<flankNextAt then return false end
            local enemyCharacter,_,enemyRoot=parts(target)
            local d=enemyRoot and ownRoot.Position-enemyRoot.Position or Vector3.zero
            local flat=Vector3.new(d.X,0,d.Z)
            local rear,route=false,nil
            if enemyRoot then local f=enemyRoot.CFrame.LookVector; rear=Flank.behind(d.X,d.Z,f.X,f.Z,config.attackRange,d.Y) end
            if config.flank then
                local combo=Core.nextCombo(now,ownCharacter:GetAttribute("Combo"),ownCharacter:GetAttribute("ComboTime"),
                    ownCharacter:GetAttribute("ForcedCombo"),human:GetState()==Enum.HumanoidStateType.Freefall)
                if combo>3 or not Contact.canStart(pendingShot,combo,now,enemyCharacter) then
                    flankMessage="等待原连段重置，保持防御"; dashRequested=false; return false
                end
            end
            local state=adapter.state
            local blocked=human.Sit or human.PlatformStand or ownRoot.Anchored or human.FloorMaterial==Enum.Material.Air
                or ownCharacter:GetAttribute("Ragdolled") or state.CheckState("Freeze") or state.CheckState("Ragdoll")
                or state.CheckState("NoRotate") or state.CheckState("Rolling")
                or Flank.attackCooling(now,driver.nextAt,state.CheckState("NoM1"),guard.held~=nil)
                or ownRoot:FindFirstChild("DashVelocity") or ownRoot:FindFirstChild("RollVelocity")
                or ownRoot:FindFirstChild("FrontDashVelocity") or ((state.BlockHeld or ownCharacter:GetAttribute("Blocking")) and not guard.held)
            local protected=enemyCharacter and (enemyCharacter:GetAttribute("GodMode") or enemyCharacter:GetAttribute("Ragdolled")
                or enemyCharacter:FindFirstChildOfClass("ForceField"))
            local reason=Flank.reason({active=active,ready=runtimeReady(ownCharacter),manual=manual,blocked=blocked,
                threat=config.flank and flankThreat(ownCharacter,ownRoot,target),
                cooldown=not (config.flank and rear) and not (adapter.dashReady() or (guard.held and adapter.dashCooldownReady())),flank=config.flank,
                targetAlive=enemyRoot~=nil,protected=protected,targetBlocking=enemyCharacter and enemyCharacter:GetAttribute("Blocking"),
                exposed=rear,
                distance=flat.Magnitude,height=d.Y,clear=true})
            if reason then flankMessage=reason; dashRequested=false; return false end
            if config.flank then
                if not rear then route=flankRoute(ownCharacter,ownRoot,enemyCharacter,enemyRoot) end
                if not rear and not route then flankMessage="两侧路线有障碍或落差"; dashRequested=false; flankNextAt=now+.3; return false end
            end
            local camera=Workspace.CurrentCamera
            if not camera then return false end
            local look=camera.CFrame.LookVector
            look=Vector3.new(look.X,0,look.Z)
            if look.Magnitude<.05 then return false end
            releaseAttack(); releaseDefense(); releaseMovement(false)
            flankAction={phase="release",player=config.flank and target or nil,flank=config.flank,route=route,
                rear=rear,look=look.Unit,startedAt=now,phaseAt=now,punches=0,character=ownCharacter,
                targetCharacter=config.flank and enemyCharacter or nil}
            dashRequested=false
            trace("FLANK_START",{flank=config.flank,side=route and route.side or 1,angle=route and route.angle,
                distance=flat.Magnitude,rear=rear})
        end
        local a=flankAction
        local c,_,r=parts(a.player)
        local d=r and ownRoot.Position-r.Position or Vector3.zero
        local flat=Vector3.new(d.X,0,d.Z)
        local protected=c and (c:GetAttribute("GodMode") or c:GetAttribute("Ragdolled") or c:FindFirstChildOfClass("ForceField"))
        local state=adapter.state
        local blocked=not runtimeReady(ownCharacter) or human.Sit or human.PlatformStand or ownRoot.Anchored
            or state.CheckState("Freeze") or state.CheckState("Ragdoll") or state.CheckState("Rolling")
            or state.CheckState("NoRotate") or ownCharacter:GetAttribute("Ragdolled")
            or ownRoot:FindFirstChild("FrontDashVelocity") or ownRoot:FindFirstChild("RollVelocity")
        local threat=a.flank and flankThreat(ownCharacter,ownRoot,a.player,Contact.pressure(a.shot,a.previousHitAt,now))
        local reason=Flank.abort({manual=manual,blocked=blocked,damaged=lastDamageAt>a.startedAt,
            threat=threat,elapsed=now-a.startedAt,flank=a.flank,alive=r~=nil and c==a.targetCharacter,
            protected=protected,distance=flat.Magnitude,height=d.Y})
        if reason then cancelFlank(reason); return false end
        local rear,dot=false,nil
        if r then local f=r.CFrame.LookVector; rear,dot=Flank.behind(d.X,d.Z,f.X,f.Z,config.attackRange,d.Y) end
        local function orient()
            local look=a.look
            if a.flank then
                local x,z=Flank.steer(d.X,d.Z,a.route.radius,a.route.side)
                if not x then return false end
                look=Vector3.new(z*a.route.side,0,-x*a.route.side)
            end
            if not steerDash(ownCharacter,human,ownRoot,look) then return false end
            local velocity=flankDriver.owned
            if velocity and velocity.Parent==ownRoot then
                -- 同步转向本次侧闪的速度向量，只保留原游戏当前速度大小。
                velocity.Velocity=ownRoot.CFrame.RightVector*(a.route and a.route.side or 1)*velocity.Velocity.Magnitude
            end
            return true
        end
        if a.phase=="release" then
            flankMessage="松防，准备"..(a.flank and "绕后" or "向右侧闪")
            guard:observeRelease(ownCharacter:GetAttribute("Blocking"),now)
            if state.BlockHeld or ownCharacter:GetAttribute("Blocking") or state.CheckState("NoM1") or state.CheckState("NoDash") then
                if now-a.phaseAt>.6 then cancelFlank("松防或收招未完成"); return false end
                return true
            end
            if a.flank and rear then a.phase="attack"; a.phaseAt=now
            elseif a.flank and not a.route then cancelFlank("目标转身，重新评估路线"); return false
            else
                if not orient() then cancelFlank("镜头或方向不可用"); return false end
                local move=ownRoot.CFrame.RightVector*(a.route and a.route.side or 1)
                if not flankPathClear(ownRoot.Position,ownRoot.Position+move*3,{ownCharacter,c}) then cancelFlank("前方没有安全落点"); return false end
                if not flankDriver:launch(adapter,ownRoot,a.route and a.route.side or 1) then cancelFlank("原侧闪拒绝：状态或冷却未结束"); return false end
                a.phase,a.phaseAt="dash",now
                trace("FLANK_DASH",{side=a.route and a.route.side or 1})
                return true
            end
        end
        if a.phase=="dash" then
            local velocity=flankDriver.owned
            if a.flank and rear then
                flankDriver:release(true)
                a.phase,a.phaseAt="attack",now
                trace("FLANK_REAR",{distance=flat.Magnitude,dot=dot,elapsed=now-a.startedAt})
            elseif not velocity or velocity.Parent~=ownRoot then
                cancelFlank(a.flank and "侧闪结束，未到可攻击的背面" or "向右侧闪完成"); return false
            elseif now-a.phaseAt>.9 then cancelFlank("绕行超时，恢复防御"); return false
            else
                if not orient() then cancelFlank("镜头被接管"); return false end
                local move=velocity.Velocity
                local length=math.clamp(move.Magnitude*.045,1.5,5)
                if move.Magnitude>.01 and not flankPathClear(ownRoot.Position,ownRoot.Position+move.Unit*length,{ownCharacter,c}) then
                    cancelFlank("绕行遇到障碍或落差"); return false
                end
                flankMessage=a.flank and "侧闪绕行，确认背面位置" or "正在向右侧闪"
                return true
            end
        end
        if a.phase=="attack" or a.phase=="struck" then
            if a.phase=="struck" and (a.punches>=(config.chain and 3 or 1) or (a.lastCombo or 0)>=3) then
                if now>=a.recoverAt then cancelFlank("绕后连击结束"); return false end
                flankMessage="绕后连击收招"; return true
            end
            local confirmed=a.phase=="struck" and Contact.canContinue(a.shot,now)
            local canFollow=confirmed and flat.Magnitude<=config.attackRange and math.abs(d.Y)<=4
            if a.phase=="attack" and not rear then cancelFlank("目标转身，等待新的背面机会"); return false end
            if a.phase=="struck" and (not Contact.pending(a.shot,now) or flat.Magnitude>config.attackRange+2.5 or math.abs(d.Y)>4) then
                cancelFlank("命中等待结束或目标脱离，恢复防御"); return false
            end
            if a.phase=="struck" and not confirmed then
                if not a.shot or now>a.shot.deadline then cancelFlank("未确认命中，恢复防御"); return false end
                flankMessage="等待本拳命中反馈"; return true
            end
            if not steerDash(ownCharacter,human,ownRoot,-flat.Unit) then cancelFlank("镜头不可用"); return false end
            local visible=ray(ownRoot.Position,r.Position-ownRoot.Position,{ownCharacter,c})==nil
            if not visible then cancelFlank("目标被遮挡"); return false end
            local ready=Flank.canStrike({alive=r~=nil,protected=protected,behind=rear or canFollow,visible=visible,
                blocked=combatBlocked(ownCharacter,human,ownRoot),cooldown=state.CheckState("NoM1") or now<driver.nextAt,
                threat=threat,punches=a.punches,chain=config.chain,lastCombo=a.lastCombo})
            if ready then
                local combo,forced=Core.nextCombo(now,ownCharacter:GetAttribute("Combo"),ownCharacter:GetAttribute("ComboTime"),
                    ownCharacter:GetAttribute("ForcedCombo"),human:GetState()==Enum.HumanoidStateType.Freefall)
                if combo>3 then cancelFlank("三段结束，等待原连段重置"); return false end
                driver.targetCharacter=c
                local previousHitAt=a.shot and a.shot.confirmedAt
                if driver:attack(adapter,ownCharacter,combo,now) then
                    if forced then ownCharacter:SetAttribute("ForcedCombo",nil) end
                    driver:release()
                    a.phase,a.punches,a.lastCombo="struck",a.punches+1,combo
                    a.previousHitAt=previousHitAt
                    a.shot=driver.lastShot
                    local timing=adapter.moves[combo]
                    a.recoverAt=math.max(driver.nextAt,now+(timing and timing.BlockedLength or .5))
                    flankAttackCount+=1
                    trace("FLANK_STRIKE",{combo=combo,punches=a.punches,distance=flat.Magnitude,dot=dot})
                end
            elseif now-a.phaseAt>.7 and a.punches==0 then cancelFlank("未能在背面窗口出拳"); return false end
            flankMessage="背面连击 "..tostring(a.punches).." 拳，遵守原普攻冷却"
            return true
        end
        return true
    end
    local function attackStep(ownCharacter, human, ownRoot, enemyCharacter, enemyRoot, deltaTime)
        if defenseBusy then driver:release(); attackMessage = counterAction and counterMessage or "自动防御优先，暂停出拳"; return end
        if not config.attack then releaseAttack(); attackMessage = "自动普攻已关闭"; return end
        if adapter and (adapter.character ~= ownCharacter or adapter.selected ~= ownCharacter:GetAttribute("SelectedCharacter")) then
            prepareAttack(ownCharacter)
        end
        if not adapter then releaseAttack(); attackMessage = adapterMessage; return end
        -- 使用原 Controls 依赖的运行环境；环境缺失时停止发送动作。
        if not runtimeReady(ownCharacter) then
            releaseAttack(); attackMessage = "游戏控制脚本或 Network 未就绪"; return
        end
        if not enemyRoot then releaseAttack(); attackMessage = "等待可攻击的玩家"; return end
        local now = os.clock()
        local manual = now < manualUntil or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or Input:IsKeyDown(Enum.KeyCode.F)
        local blocked = combatBlocked(ownCharacter, human, ownRoot)
        local difference = enemyRoot.Position - ownRoot.Position
        local flat = Vector3.new(difference.X, 0, difference.Z)
        local protected = enemyCharacter:GetAttribute("GodMode") or enemyCharacter:GetAttribute("Ragdolled")
            or enemyCharacter:FindFirstChildOfClass("ForceField") ~= nil
        if not manual and not manualMovement() and not blocked and not protected and flat.Magnitude > 0.05 then
            if not rotationRecord then rotationRecord = { human = human, autoRotate = human.AutoRotate } end
            human.AutoRotate = false
            ownRoot.CFrame = ownRoot.CFrame:Lerp(CFrame.lookAt(ownRoot.Position, ownRoot.Position + flat), Core.alpha(24, deltaTime))
        else releaseRotation() end
        local facing = flat.Magnitude <= 0.05 and 1 or ownRoot.CFrame.LookVector:Dot(flat.Unit)
        local visible = false
        if flat.Magnitude <= config.attackRange and math.abs(difference.Y) <= 4 then
            visible = ray(ownRoot.Position + Vector3.new(0, 1, 0), difference, {ownCharacter, enemyCharacter}) == nil
        end
        local reason = Core.attackReason({ enabled = active and config.attack, ready = true, manual = manual,
            selfBlocked = blocked, targetAlive = true, targetProtected = protected, distance = flat.Magnitude,
            height = math.abs(difference.Y), range = config.attackRange, visible = visible, facing = facing,
            cooldown = adapter.state.CheckState("NoM1") or now < driver.nextAt })
        if reason then
            if reason ~= "等待出拳 / 收招冷却" then driver:release() end
            attackMessage = reason
            return
        end
        local combo, usedForced = Core.nextCombo(now, ownCharacter:GetAttribute("Combo"),
            ownCharacter:GetAttribute("ComboTime"), ownCharacter:GetAttribute("ForcedCombo"),
            human:GetState() == Enum.HumanoidStateType.Freefall)
        if combo>3 then driver:release(); attackMessage="三段结束，等待原连段重置"; return end
        if combo>1 and not config.chain then driver:release(); attackMessage="单拳完成，等待原连段重置"; return end
        if not Contact.canStart(pendingShot,combo,now,enemyCharacter) then
            driver:release(); attackMessage="未确认上一拳命中，等待原连段重置"; return
        end
        driver.targetCharacter=enemyCharacter
        if driver:attack(adapter, ownCharacter, combo, now) then
            driver:release()
            if usedForced then ownCharacter:SetAttribute("ForcedCombo", nil) end
            attackMessage = string.format("%s · 发起第 %d 段普攻", adapter.name, combo)
        end
    end
    local function step(deltaTime)
        if not active then return end
        local began = os.clock()
        if not focused or Input:GetFocusedTextBox() or GuiService.MenuIsOpen then stop("输入或菜单打开，已暂停"); return end
        local ownCharacter, human, ownRoot = parts(me)
        if not ownRoot then stop("角色死亡或重生，已暂停"); return end
        pumpDefense(deltaTime)
        if not active then return end
        scanTimer += deltaTime
        local enemyCharacter, _, enemyRoot = parts(target)
        if scanTimer >= 0.05 or (target and not enemyRoot) then
            scanTimer = 0
            scan(ownCharacter, ownRoot)
            enemyCharacter, _, enemyRoot = parts(target)
        end
        if counterAction then
            target = counterAction.player
            enemyCharacter, _, enemyRoot = parts(target)
        end
        local wasFlanking=flankAction~=nil
        local flanking=flankStep(ownCharacter,human,ownRoot)
        if wasFlanking and not flanking then pumpDefense(deltaTime) end
        if not active then return end
        if flankAction and flankAction.player then target=flankAction.player; enemyCharacter,_,enemyRoot=parts(target) end
        if evadeAction then
            target=evadeAction.player
            message=defenseMessage
        elseif flanking then
            message=flankMessage
            releaseMovement(false)
        elseif counterAction and (counterAction.approachDash or counterAction.weaving) then
            message=counterMessage
            releaseMovement(false)
        elseif enemyRoot and (enemyRoot.Position - ownRoot.Position).Magnitude <= config.range then
            cameraStep(ownCharacter, ownRoot, enemyCharacter, enemyRoot, deltaTime)
            if not active then return end
            message = "正在跟踪 · 镜头每帧更新"
            if config.chase and not defenseBusy and not combatBlocked(ownCharacter, human, ownRoot)
                and not (adapter and adapter.state.CheckState("NoMovement")) then
                local manual = manualMovement()
                local difference = enemyRoot.Position - ownRoot.Position
                local flat = Vector3.new(difference.X, 0, difference.Z)
                local blocked = flat.Magnitude > config.stopDistance and ray(ownRoot.Position,
                    flat.Unit * math.min(flat.Magnitude, 3), {ownCharacter, enemyCharacter}) ~= nil
                if manual then releaseMovement(true); message = "手动移动中，自动追击让出"
                else
                    local amount = Core.moveAmount(flat.Magnitude, config.stopDistance, blocked, false)
                    human:Move(amount > 0 and flat.Unit or Vector3.zero, false)
                    movingHuman = human
                    message = blocked and "前方有障碍，等待手动绕行" or (amount > 0 and "正在普通移动追击" or "已到达追击停距")
                end
            else releaseMovement(manualMovement()) end
            attackStep(ownCharacter, human, ownRoot, enemyCharacter, enemyRoot, deltaTime)
            facingStep(ownCharacter, human, ownRoot, enemyRoot)
        else
            target = nil
            releaseMovement(false)
            releaseCamera()
            if defenseBusy then driver:release() else releaseAttack() end
            attackMessage = defenseBusy and "自动防御优先，暂停出拳"
                or (config.attack and (adapter and "等待可攻击的玩家" or adapterMessage) or "自动普攻已关闭")
            message = "范围内没有可选玩家，等待加载或出现"
        end
        sampleGuardMotion(ownCharacter,ownRoot)
        ticks += 1; measureTimer += deltaTime; uiTimer += deltaTime
        if measureTimer >= 0.5 then updateHz = ticks / measureTimer; ticks, measureTimer = 0, 0 end
        lastCostMs = (os.clock() - began) * 1000
        if uiTimer >= 0.15 then uiTimer = 0; refresh() end
    end
    startupStage = "绑定按钮和输入"
    local function competingHit(shot,now)
        local victimRoot=shot.target and shot.target:FindFirstChild("HumanoidRootPart")
        if not victimRoot then return true end
        for _,other in ipairs(players) do
            if other~=me and other.Character~=shot.target then
                local c,h,r=parts(other)
                if r and (r.Position-victimRoot.Position).Magnitude<=14 then
                    local relative=r.CFrame:PointToObjectSpace(victimRoot.Position)
                    if math.abs(relative.X)<=6.25 and -relative.Z>=-3.25 and -relative.Z<=10.5 and math.abs(relative.Y)<=8 then
                        local watch=watchers[other]
                        local record=watch and watch.latest
                        if record and record.profile.combo==shot.combo and now-record.startedAt>=record.profile.first-.1
                            and now-record.startedAt<=record.profile.last+.4 then return true end
                        local animator=h:FindFirstChildOfClass("Animator")
                        if animator then
                            for _,track in ipairs(animator:GetPlayingAnimationTracks()) do
                                local p=track.Animation and Defense.profile(track.Animation.AnimationId)
                                if p and p.combo==shot.combo and track.TimePosition>=p.first-.1
                                    and track.TimePosition<=p.last+.4 then return true end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    local renderFeedback = ReplicatedStorage:FindFirstChild("ClientRenderRequest")
    if renderFeedback and renderFeedback:IsA("RemoteEvent") then
        connect(renderFeedback.OnClientEvent,function(payload)
            if type(payload)~="table" then return end
            if active and config.defense and (payload.Request=="SmallBlock" or payload.Request=="LargeBlock")
                and payload.On==me.Character then
                local watch=defenseTarget and watchers[defenseTarget]
                local r=watch and watch.skill
                pcall(trace,"GUARD_FEEDBACK",{source=payload.Request,guardTarget=defenseTarget and defenseTarget.UserId,
                    trackedSkill=r and Skill.active(r,os.clock()) and r.profile.name or nil})
            end
            if active and config.defense and typeof(payload.U)=="Instance" and payload.U:IsA("Model") then
                local player=Players:GetPlayerFromCharacter(payload.U)
                local watch=player and watchers[player]
                if player~=me and watch and watch.character==payload.U then
                    local profile=Skill.event(payload.Request,payload.U:GetAttribute("SelectedCharacter"))
                    if profile then observeSkill(player,watch,profile,os.clock(),0,false,1)
                    elseif watch.skill and ((payload.Request=="BFA" and watch.skill.profile==Skill.profiles.body)
                        or (payload.Request=="EndFlashstepFury" and watch.skill.profile==Skill.profiles.fury)
                        or (payload.Request=="LightningFlashH" and watch.skill.profile==Skill.profiles.lightning)) then
                        watch.skill.ended=true
                        pcall(trace,"SKILL_END",{player=player.UserId,name=watch.skill.profile.name,source=payload.Request})
                        pumpDefense(0)
                    end
                end
            end
            if payload.Request=="ME" then
                if active and pendingShot then
                    local now=os.clock()
                    if Contact.feedback(pendingShot,payload,now,competingHit(pendingShot,now)) then
                        hitCount+=1
                        pcall(trace,"HIT_CONFIRMED",{combo=pendingShot.combo,elapsed=now-pendingShot.sentAt,target=pendingShot.target.Name})
                        pumpDefense(0)
                    end
                end
                return
            end
            if payload.Request~="SmallBlock" or payload.On~=me.Character then return end
            if active and config.defense and config.counter and config.gap and guard.held then
                blockFeedback={at=os.clock()}
                pcall(trace,"BLOCK_HIT",{source="SmallBlock"})
                pumpDefense(0)
            end
        end)
    end
    connect(toggle.Activated, start)
    connect(halt.Activated, function() stop() end)
    connect(close.Activated, cleanup)
    connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fitPanel)
    local function toggleAttack()
        config.attack = not config.attack
        if config.attack then
            config.stopDistance = math.min(config.stopDistance, config.attackRange - 1)
            stopBox.Text = tostring(config.stopDistance)
            if not adapter and not loading then prepareAttack(me.Character) end
            attackMessage = active and "自动普攻已开启" or "自动普攻已开启，按 F6 开始"
        else releaseAttack(); attackMessage = "自动普攻已关闭" end
        refresh()
    end
    connect(attackButton.Activated, toggleAttack)
    local function toggleFacing()
        config.face = not config.face
        if not config.face then releaseRotation()
        elseif active and not adapter and not loading then prepareAttack(me.Character) end
        pcall(trace,"FACING_TOGGLE",{enabled=config.face})
        refresh()
    end
    connect(faceButton.Activated, toggleFacing)
    local function toggleDefense()
        config.defense = not config.defense
        if config.defense then
            watchTimer = 0.05
            if not adapter and not loading then prepareAttack(me.Character) end
            defenseMessage = active and "开始监测附近普攻" or "自动防御已开启，按 F6 开始"
        else releaseDefense(); clearWatchers(); defenseMessage = "自动防御已关闭" end
        diagnostic("自动防御=" .. tostring(config.defense))
        refresh()
    end
    connect(defenseButton.Activated, toggleDefense)
    connect(evadeButton.Activated,function()
        config.evade=not config.evade
        if not config.evade then cancelEvade("下砸自动避让已关闭") end
        refresh()
    end)
    connect(jumpButton.Activated,function()
        config.jump=not config.jump
        if not config.jump and counterAction and counterAction.jumpOpportunity then cancelCounter("起跳抢断关闭"); driver:release() end
        refresh()
    end)
    local function toggleCounter()
        config.counter = not config.counter
        cancelCounter(config.counter and "等待格挡命中或收尾窗口" or "自动反击已关闭")
        driver:release()
        diagnostic("自动反击=" .. tostring(config.counter))
        refresh()
    end
    connect(counterButton.Activated, toggleCounter)
    connect(gapButton.Activated,function()
        config.gap=not config.gap
        blockFeedback=nil
        cancelCounter(config.gap and "等待挡中反馈或完整空招，尝试抢攻" or "只在收尾窗口反击")
        driver:release()
        refresh()
    end)
    connect(chainButton.Activated,function()
        config.chain=not config.chain
        if not config.chain then cancelCounter("已切换为单拳反击"); driver:release() end
        refresh()
    end)
    connect(interruptButton.Activated,function()
        config.interrupt=not config.interrupt
        if counterAction and counterAction.interruptOpportunity then cancelCounter("抢断策略切换，恢复防御"); driver:release() end
        refresh()
    end)
    connect(interruptStyleButton.Activated,function()
        config.interruptStyle=({advance="front",front="weave",weave="advance"})[config.interruptStyle] or "advance"
        cancelCounter("抢断方式切换，恢复防御")
        cancelFlank("抢断方式已切换")
        driver:release()
        for _,watch in pairs(watchers) do
            if watch.latest then watch.latest.interruptLogged=nil; watch.latest.interruptFitLogged=nil end
        end
        pcall(trace,"INTERRUPT_STYLE",{style=config.interruptStyle})
        refresh()
    end)
    local function requestDash()
        if not Interrupt.canFlank(config.interruptStyle) then refresh(); return end
        if not active then flankMessage="请先按 F6 开始"; refresh(); return end
        if flankAction then return end
        if not adapter and not loading then prepareAttack(me.Character) end
        dashRequested=true
        flankMessage=config.flank and "已请求绕后" or "已请求向右侧闪"
        refresh()
    end
    connect(dashButton.Activated,requestDash)
    connect(flankButton.Activated,function()
        if not Interrupt.canFlank(config.interruptStyle) then refresh(); return end
        config.flank=not config.flank
        cancelFlank(config.flank and "等待近处对手格挡，自动侧闪绕后" or "自动绕后已关闭；Z 向右侧闪")
        if config.flank and not adapter and not loading then prepareAttack(me.Character) end
        refresh()
    end)
    connect(preemptButton.Activated, function()
        config.preempt = not config.preempt
        releaseDefense()
        watchTimer = 0.05
        defenseMessage = config.preempt and "近身预防开启，贴近敌人会提前举防" or "只检测已识别到的攻击"
        diagnostic("近身预防=" .. tostring(config.preempt))
        refresh()
    end)
    connect(chase.Activated, function()
        config.chase = not config.chase
        if not config.chase then releaseMovement(false) end
        refresh()
    end)
    connect(visibility.Activated, function() config.visibleOnly = not config.visibleOnly; target, scanTimer = nil, 0.05; refresh() end)
    connect(speed.Activated, function() config.response = config.response == 24 and 12 or 24; refresh() end)
    connect(reselect.Activated, function() target, scanTimer = nil, 0.05; refresh() end)
    connect(rangeBox.FocusLost, function()
        config.range = Core.number(rangeBox.Text, config.range, 10, 5000)
        rangeBox.Text, target, scanTimer = tostring(config.range), nil, 0.05
    end)
    connect(stopBox.FocusLost, function()
        config.stopDistance = Core.number(stopBox.Text, config.stopDistance, 2, 40)
        if config.attack then config.stopDistance = math.min(config.stopDistance, config.attackRange - 1) end
        stopBox.Text = tostring(config.stopDistance)
    end)
    connect(attackRangeBox.FocusLost, function()
        config.attackRange = Core.number(attackRangeBox.Text, config.attackRange, 3, 8)
        attackRangeBox.Text = tostring(config.attackRange)
        if config.attack then
            config.stopDistance = math.min(config.stopDistance, config.attackRange - 1)
            stopBox.Text = tostring(config.stopDistance)
        end
    end)
    connect(defenseRangeBox.FocusLost, function()
        config.defenseRange = Core.number(defenseRangeBox.Text, config.defenseRange, 6, 24)
        defenseRangeBox.Text, watchTimer = tostring(config.defenseRange), 0.05
    end)
    connect(Input.InputBegan, function(input, processed)
        if input.KeyCode == Enum.KeyCode.F9 then stop("F9：已停止")
        elseif input.KeyCode == Enum.KeyCode.F5 and not processed and not Input:GetFocusedTextBox() then toggleFacing()
        elseif input.KeyCode == Enum.KeyCode.F6 and not processed and not Input:GetFocusedTextBox() then start()
        elseif input.KeyCode == Enum.KeyCode.F7 and not processed and not Input:GetFocusedTextBox() then toggleAttack()
        elseif input.KeyCode == Enum.KeyCode.F8 and not processed and not Input:GetFocusedTextBox() then toggleDefense()
        elseif input.KeyCode == Enum.KeyCode.F10 and not processed and not Input:GetFocusedTextBox() then toggleCounter()
        elseif input.KeyCode == Enum.KeyCode.Z and not processed and not Input:GetFocusedTextBox() then requestDash()
        elseif input.KeyCode == Enum.KeyCode.Escape and active then stop("菜单打开，已暂停") end
        if not processed and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.G
            or input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.Two or input.KeyCode == Enum.KeyCode.Three
            or input.KeyCode == Enum.KeyCode.Four or input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.R) then
            manualUntil = os.clock() + 0.65
            if pendingShot then pendingShot.cancelled=true end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then driver:handoff() end
            if input.KeyCode == Enum.KeyCode.F then guard:handoff() end
            cancelFlank("手动操作优先")
            releaseDefense()
            releaseAttack()
        end
    end)
    connect(Input.TextBoxFocused, function() if active then stop("聊天或文本框打开，已暂停") end end)
    connect(Input.WindowFocusReleased, function() focused = false; if active then stop("已切出游戏，按 F6 重新开始") end end)
    connect(Input.WindowFocused, function() focused = true end)
    connect(GuiService.MenuOpened, function() if active then stop("游戏菜单打开，已暂停") end end)
    connect(me.CharacterRemoving, function()
        stop("角色重生，按 F6 重新开始")
        clearMonitor()
        loadGeneration += 1
        adapter, loading, adapterMessage = nil, false, "等待新角色，按 F6 重新加载"
        driver.nextAt = 0
    end)
    connect(Players.PlayerAdded, function() players = Players:GetPlayers(); scanTimer = 0.05 end)
    connect(Players.PlayerRemoving, function(other)
        local remaining = {}
        for _, item in ipairs(players) do if item ~= other then table.insert(remaining, item) end end
        players = remaining
        if target == other then target, scanTimer = nil, 0.05 end
    end)
    local dragging, dragInput, dragStart, panelStart
    connect(title.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, panelStart = true, input.Position, panel.Position
        end
    end)
    connect(title.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    connect(Input.InputChanged, function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X, panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
        end
    end)
    connect(Input.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
        if closed then return end
        local ok, reason = xpcall(step, traceback, deltaTime)
        if not ok then fail(reason) end
    end)
    refresh()
    startupStage = "初始化完成"
    diagnostic("v3.18 面板已创建；侧闪防御优先读取已接收位置快照；F5 手动面向目标默认开；技能应对与命中三段保留；F6 总开关 / F7 普攻 / F8 防御 / F9 全停")
    print("[客户端自动找人 v3.18] F6 总开关 / F7 普攻 / F8 防御 / F9 全停；攻防总开关默认关闭。")
end
local ok, reason = xpcall(main, traceback)
if not ok then
    if emergencyCleanup then pcall(emergencyCleanup) end
    diagnostic("启动失败：" .. tostring(reason))
    warn("[客户端自动找人] 启动失败：" .. tostring(reason))
    pcall(function()
        local player = game:GetService("Players").LocalPlayer
        local parent = player and player:FindFirstChildOfClass("PlayerGui")
        if not parent then return end
        local gui = Instance.new("ScreenGui")
        gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.Parent = "ClientFinderError", false, 10000, parent
        local text = Instance.new("TextBox")
        text.AnchorPoint, text.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
        text.Size, text.BackgroundColor3 = UDim2.fromScale(0.8, 0.4), Color3.fromRGB(45, 24, 30)
        text.TextColor3, text.TextSize = Color3.fromRGB(255, 224, 224), 16
        text.ClearTextOnFocus, text.MultiLine, text.TextWrapped = false, true, true
        text.Text = "自动找人 v3.18 启动失败（可复制）\n" .. startupStage .. "\n" .. tostring(reason)
        text.Parent = gui
    end)
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "客户端自动找人启动失败", Text = tostring(reason):sub(1, 180), Duration = 12 }) end)
end
