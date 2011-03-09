package net.systemeD.halcyon.connection {

    import flash.events.*;

	import flash.system.Security;
	import flash.net.*;
    import org.iotashan.oauth.*;

    /**
    * XMLBaseConnection is the common code between connecting to an OSM server
    * (i.e. XMLConnection) and connecting to a standalone .osm file (i.e. OSMConnection)
    * and so mainly concerns itself with /map -call-ish related matters
    */
	public class XMLBaseConnection extends Connection {

		public function XMLBaseConnection() {
		}
		
        protected function loadedMap(event:Event):void {
            var map:XML = new XML(URLLoader(event.target).data);
            var id:Number;
            var version:uint;
            var uid:Number;
            var timestamp:String;
            var user:String;
            var tags:Object;
            var node:Node, newNode:Node;
            var unusedNodes:Object={};

			var minlon:Number, maxlon:Number, minlat:Number, maxlat:Number;
			var singleEntityRequest:Boolean=true;
			if (map.bounds.@minlon.length()) {
				minlon=map.bounds.@minlon;
				maxlon=map.bounds.@maxlon;
				minlat=map.bounds.@minlat;
				maxlat=map.bounds.@maxlat;
				singleEntityRequest=false;
			}

            for each(var relData:XML in map.relation) {
                id = Number(relData.@id);
                version = uint(relData.@version);
                uid = Number(relData.@uid);
                timestamp = relData.@timestamp;
                user = relData.@user;
                
                var rel:Relation = getRelation(id);
                if ( rel == null || !rel.loaded ) {
                    tags = parseTags(relData.tag);
                    var members:Array = [];
                    for each(var memberXML:XML in relData.member) {
                        var type:String = memberXML.@type.toLowerCase();
                        var role:String = memberXML.@role;
                        var memberID:Number = Number(memberXML.@ref);
                        var member:Entity = null;
                        if ( type == "node" ) {
                            member = getNode(memberID);
                            if ( member == null ) {
                                member = new Node(memberID,0,{},false,0,0);
                                setNode(Node(member),true);
                            } else if (member.isDeleted()) {
                                member.setDeletedState(false);
                            }
                        } else if ( type == "way" ) {
                            member = getWay(memberID);
                            if (member == null) {
                                member = new Way(memberID,0,{},false,[]);
                                setWay(Way(member),true);
                            }
                        } else if ( type == "relation" ) {
                            member = getRelation(memberID);
                            if (member == null) {
                                member = new Relation(memberID,0,{},false,[]);
                                setRelation(Relation(member),true);
                            }
                        }
                        
                        if ( member != null )
                            members.push(new RelationMember(member, role));
                    }
                    
                    if ( rel == null )
                        setRelation(new Relation(id, version, tags, true, members, uid, timestamp, user), false);
                    else {
                        rel.update(version, tags, true, false, members, uid, timestamp, user);
                        sendEvent(new EntityEvent(NEW_RELATION, rel), false);
                    }
                }
            }

            for each(var nodeData:XML in map.node) {
				id = Number(nodeData.@id);
				node = getNode(id);
				newNode = new Node(id, 
				                   uint(nodeData.@version), 
				                   parseTags(nodeData.tag),
				                   true, 
				                   Number(nodeData.@lat),
				                   Number(nodeData.@lon),
				                   Number(nodeData.@uid),
				                   nodeData.@timestamp),
				                   nodeData.@user;
				
				if ( singleEntityRequest ) {
					// it's a revert request, so create/update the node
					setOrUpdateNode(newNode, true);
				} else if ( node == null || !node.loaded) {
					// the node didn't exist before, so create/update it
					newNode.parentsLoaded=newNode.within(minlon,maxlon,minlat,maxlat);
					setOrUpdateNode(newNode, true);
				} else {
					// the node's already in memory, but store it in case one of the new ways needs it
					if (newNode.within(minlon,maxlon,minlat,maxlat)) newNode.parentsLoaded=true;
					unusedNodes[id]=newNode;
				}
			}
            
            for each(var data:XML in map.way) {
                id = Number(data.@id);
                version = uint(data.@version);
                uid = Number(data.@uid);
                timestamp = data.@timestamp;
                user = data.@user;

                var way:Way = getWay(id);
                if ( way == null || !way.loaded || singleEntityRequest) {
                    var nodes:Array = [];
                    for each(var nd:XML in data.nd) {
						var nodeid:Number=Number(nd.@ref)
						if (getNode(nodeid).isDeleted() && unusedNodes[nodeid]) { 
							setOrUpdateNode(unusedNodes[nodeid], true); 
						}
                        nodes.push(getNode(nodeid));
					}
                    tags = parseTags(data.tag);
                    if ( way == null ) {
                        setWay(new Way(id, version, tags, true, nodes, uid, timestamp, user),false);
                    } else {
						waycount++;
                        way.update(version, tags, true, true, nodes, uid, timestamp, user);
                        sendEvent(new EntityEvent(NEW_WAY, way), false);
                    }
                }
            }
            
            registerPOINodes();
            dispatchEvent(new Event(LOAD_COMPLETED));
        }
        
        protected function registerPOINodes():void {
            for each (var nodeID:Number in getAllNodeIDs()) {
                var node:Node = getNode(nodeID);
                if (!node.hasParentWays)
                    registerPOI(node);
            }
        }

        protected function parseTags(tagElements:XMLList):Object {
            var tags:Object = {};
            for each (var tagEl:XML in tagElements)
                tags[tagEl.@k] = tagEl.@v;
            return tags;
        }

	}
}
