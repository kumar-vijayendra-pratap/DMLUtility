/* *****************************************************************************************************************************   
    Class Name    : DML_Utility
    Description   : This Class is used as Util Class for DML Operations
    CreatedDate   : 18/09/2023 
    Version       : 1.0
    Author        : Kumar
    Reference     : Initial Implementation
    ---------------------------------------------------  Revision History -----------------------------------------------
    Sno      Version            Modification Done                           Modified By            Modified Date                  
     1        1.0            Initial Implementation                          Kumar           		18/09/2023    
******************************************************************************************************************************* */
public class DML_Utility {
	// Items in the following set must be entered in lower case
	private static Set<String> exceptionValues = new Set<String> {'id','isdeleted','createddate','systemmodstamp','lastmodifiedbyid','createdbyid','lastmodifieddate'};

	private static Map<Operation,Map<SObjectType,List<String>>> cachedRestrictedFields = new Map<Operation,Map<SObjectType,List<String>>>();
	
	public enum Operation {OP_INSERT,OP_UPDATE,OP_DELETE,OP_UPSERT}
	
	// CRUD/FLS-safe DML operations. These honor the CRUD and FLS permissions of the running user
	public static void insertAsUser(sObject obj){performDMLOperation(new List<sObject>{obj},Operation.OP_INSERT);}
	public static void updateAsUser(sObject obj){performDMLOperation(new List<sObject>{obj},Operation.OP_UPDATE);}
	public static void upsertAsUser(sObject obj){performDMLOperation(new List<sObject>{obj},Operation.OP_UPSERT);}
	public static void deleteAsUser(sObject obj){performDMLOperation(new List<sObject>{obj},Operation.OP_DELETE);}
	
	public static void insertAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_INSERT);}
	public static void updateAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_UPDATE);}
	public static void upsertAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_UPSERT);}
	public static void deleteAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_DELETE);}

	// CRUD/FLS-safe DML operations. These honor the CRUD and FLS permissions of the running user //Returns Databse.SaveResult
	public static List<Database.SaveResult> insertAsUser(sObject obj,boolean allOrNone){return (performDMLOperation(new List<sObject>{obj},allOrNone,Operation.OP_INSERT));}
	public static List<Database.SaveResult> updateAsUser(sObject obj,boolean allOrNone){return (performDMLOperation(new List<sObject>{obj},allOrNone,Operation.OP_UPDATE));}
	public static List<Database.UpsertResult> upsertAsUser(sObject obj,boolean allOrNone,Schema.SObjectField externalId){return (performUpsertDMLOperation(new List<sObject>{obj},allOrNone,externalId,Operation.OP_UPSERT));}
	public static List<Database.DeleteResult> deleteAsUser(sObject obj,boolean allOrNone){return (performDeleteDMLOperation(new List<sObject>{obj},allOrNone,Operation.OP_DELETE));}
	
	public static List<Database.SaveResult> insertAsUser(List<SObject> objList,boolean allOrNone){return (performDMLOperation(objList,allOrNone,Operation.OP_INSERT));}
	public static List<Database.SaveResult> updateAsUser(List<SObject> objList,boolean allOrNone){return (performDMLOperation(objList,allOrNone,Operation.OP_UPDATE));}
	public static List<Database.UpsertResult> upsertAsUser(List<SObject> objList,boolean allOrNone,Schema.SObjectField externalId){return (performUpsertDMLOperation(objList,allOrNone,externalId,Operation.OP_UPSERT));}
	public static List<Database.DeleteResult> deleteAsUser(List<SObject> objList,boolean allOrNone){return (performDeleteDMLOperation(objList,allOrNone,Operation.OP_DELETE));}
	
	// Pass-thru methods to raw DML operations. // Use these sparingly, and only with good reason, since the DML operations are not CRUD/FLS safe
	public static void insertAsSystem(sObject obj){ insert obj; }
	public static void updateAsSystem(sObject obj){ update obj; }
	public static void upsertAsSystem(sObject obj){ upsert obj; }
	public static void deleteAsSystem(sObject obj){ delete obj; }

	public static void insertAsSystem(List<SObject> objList){ insert objList; }
	public static void updateAsSystem(List<SObject> objList){ update objList; }
	public static void upsertAsSystem(List<SObject> objList){ upsert objList;}
	public static void deleteAsSystem(List<SObject> objList){ delete objList; }

	// Pass-thru methods to raw DML operations. // Use these sparingly, and only with good reason, since the DML operations are not CRUD/FLS safe //Returns Databse.SaveResult
	public static Database.SaveResult insertAsSystem(sObject obj,boolean allOrNone){ return Database.insert(obj,allOrNone); }
	public static Database.SaveResult updateAsSystem(sObject obj,boolean allOrNone){ return Database.update(obj,allOrNone); }
	public static Database.UpsertResult upsertAsSystem(sObject obj,boolean allOrNone,Schema.SObjectField externalId){ return Database.upsert(obj,externalId,allOrNone); }
	public static Database.DeleteResult deleteAsSystem(sObject obj,boolean allOrNone){ return Database.delete(obj,allOrNone); }

	public static List<Database.SaveResult> insertAsSystem(List<SObject> objList,boolean allOrNone){ return Database.insert(objList,allOrNone); }
	public static List<Database.SaveResult> updateAsSystem(List<SObject> objList,boolean allOrNone){ return Database.update(objList,allOrNone); }
	public static List<Database.UpsertResult> upsertAsSystem(List<SObject> objList,boolean allOrNone,Schema.SObjectField externalId){ return Database.upsert(objList,externalId,allOrNone); }
	public static List<Database.DeleteResult> deleteAsSystem(List<SObject> objList,boolean allOrNone){ return Database.delete(objList,allOrNone); }
	
	// Custom Exception Classes
	public virtual class DMLManagerException extends Exception{
		public SObjectType objType {get; private set;}
		public Operation op{get; private set;}
	}

	public class CRUDException extends DMLManagerException{
		public CRUDException(SObjectType objType, Operation op){
			this('Access Denied: ' + op + ' on ' + objType);
			this.objType = objType;
			this.op = op;
		}
	}
 
	public class FLSException extends DMLManagerException{
		public SObjectField field{get; private set;}	
		public FLSException(SObjectType objType, SObjectField field, Operation op){
			this('Access Denied: ' + op + ' on ' + objType + '.' + field);
			this.objType = objType;
			this.op = op;
			this.field = field;
		}
	}
		
	/**
	*@Description: Method to perform DML Operation
	*@param: objList,dmlOperation
	*@return: void
	*/
	private static void performDMLOperation(List<SObject> objList,Operation dmlOperation){
		Map<SObjectType,List<Id>> objTypeMap = analyzeDMLCollection(objList, dmlOperation);

		checkCRUDPermission(objTypeMap.keySet(),dmlOperation);

		if(dmlOperation == Operation.OP_INSERT){
			for(SObject obj : objList){
				checkCreateAction(obj);
			}
		} else if (dmlOperation == Operation.OP_UPDATE || dmlOperation == Operation.OP_UPSERT){
			
			Map<Id,SObject> existingRecords = getExistingRecords(objTypeMap);

			for(SObject obj : objList){
				SObject existingRecord = existingRecords.get(obj.Id);
				if(obj.id != null){
					checkUpdateAction(obj,existingRecord);
				} else {
					checkCreateAction(obj);
				}
			}
		}
		// If no errors have been thrown to this point, execute the dml operation.
		if(dmlOperation == Operation.OP_INSERT){insert objList;} 
			else if (dmlOperation == Operation.OP_UPDATE){update objList;} 
				else if (dmlOperation == Operation.OP_UPSERT){upsert objList;}
					else if (dmlOperation == Operation.OP_DELETE){delete objList;}
	}

	/**
	*@Description: Method to perform DML Operation
	*@param: obj,allOrNone,dmlOperation
	*@return: List<Database.SaveResult>
	*/
	private static List<Database.SaveResult> performDMLOperation(List<SObject> objList,boolean allOrNone,Operation dmlOperation){
		Map<SObjectType,List<Id>> objTypeMap = analyzeDMLCollection(objList, dmlOperation);

		checkCRUDPermission(objTypeMap.keySet(),dmlOperation);

		if(dmlOperation == Operation.OP_INSERT){
			for(SObject obj : objList){
				checkCreateAction(obj);
			}
		} else if (dmlOperation == Operation.OP_UPDATE){
			
			Map<Id,SObject> existingRecords = getExistingRecords(objTypeMap);

			for(SObject obj : objList){
				SObject existingRecord = existingRecords.get(obj.Id);
				if(obj.id != null){
					checkUpdateAction(obj,existingRecord);
				} else {
					checkCreateAction(obj);
				}
			}
		}
		// If no errors have been thrown to this point, execute the dml operation.
		if(dmlOperation == Operation.OP_INSERT){return Database.insert(objList,allOrNone);} 
			else if (dmlOperation == Operation.OP_UPDATE){return Database.update(objList,allOrNone);}

		return null;
	}

	/**
	*@Description: Method to perform Upsert DML Operation
	*@param: obj,allOrNone,externalIdField,dmlOperation
	*@return: List<Database.UpsertResult>
	*/
	private static List<Database.UpsertResult> performUpsertDMLOperation(List<SObject> objList,boolean allOrNone,Schema.SObjectField externalIdField,Operation dmlOperation){
		Map<SObjectType,List<Id>> objTypeMap = analyzeDMLCollection(objList, dmlOperation);

		checkCRUDPermission(objTypeMap.keySet(),dmlOperation);

		if(dmlOperation == Operation.OP_UPSERT){
			
			Map<Id,SObject> existingRecords = getExistingRecords(objTypeMap);

			for(SObject obj : objList){
				SObject existingRecord = existingRecords.get(obj.Id);
				if(obj.id != null){
					checkUpdateAction(obj,existingRecord);
				} else {
					checkCreateAction(obj);
				}
			}
		}
		// If no errors have been thrown to this point, execute the dml operation.
		if (dmlOperation == Operation.OP_UPSERT){return Database.upsert(objList,externalIdField,allOrNone);}

		return null;
	}

	/**
	*@Description: Method to perform Delete DML Operation
	*@param: obj,allOrNone,dmlOperation
	*@return: List<Database.DeleteResult>
	*/
	private static List<Database.DeleteResult> performDeleteDMLOperation(List<SObject> objList,boolean allOrNone,Operation dmlOperation){
		Map<SObjectType,List<Id>> objTypeMap = analyzeDMLCollection(objList, dmlOperation);

		checkCRUDPermission(objTypeMap.keySet(),dmlOperation);

		// If no errors have been thrown to this point, execute the dml operation.
		if (dmlOperation == Operation.OP_DELETE){return Database.delete(objList,allOrNone);}

		return null;
	}
	
	/**
	*@Description: Method to perform Upsert
	*@param: List of sObjects
	*@return: void
	*/
	private static void upsertCollection(List<SObject> objList){
		// This is to deal with a call to upsertAsUser with a singular object.
		// Since we wrap that into a List<SObject> (which can't be passed into an upsert)
		// we unpack it and upsert the object individually.
		if(objList.size() == 1){
			upsert objList.get(0);
		} else {
			upsert objList;
		}
	} 
	
	/**
	*@Description: Method to get Field Map
	*@param: obj
	*@return: Map<String,Object>
	*/
	private static Map<String,Object> getFieldMapFromExistingSObject(SObject obj){
		// Get actual fields present in object.  This serialization technique removes implicit nulls.
		String s = JSON.serialize(obj);
		Map<String,Object> fieldsMap = (Map<String,Object>) JSON.deserializeUntyped(s);
		fieldsMap.remove('attributes');
		return fieldsMap;		
	}
	
	/**
	*@Description: Method to check Create Action
	*@param: obj
	*@return: void
	*/
	private static void checkCreateAction(SObject obj){
		List<String> restrictedFields = cachedRestrictedFields.get(Operation.OP_INSERT).get(obj.getSObjectType());
		//Save ourselves a trip through the loop below if there are no restricted fields
		if(restrictedFields == null || restrictedFields.isEmpty()){
			return;
		}

		Map<String,Object> fieldsMap = getFieldMapFromExistingSObject(obj);
		
		// If any restricted fields are present, throw an exception
		for(String fieldName : restrictedFields){
			if(fieldsMap.get(fieldName) != null){ // if any of the restricted fields are present in the candidate, throw an exception
				throw new FLSException(obj.getSObjectType(),obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),Operation.OP_INSERT);
			}
		}  
	}

	/**
	*@Description: Method to check Update Action
	*@param: obj,existingRecord
	*@return: void
	*/
	private static void checkUpdateAction(SObject obj, SObject existingRecord){
		List<String> restrictedFields = cachedRestrictedFields.get(Operation.OP_UPDATE).get(obj.getSObjectType());
		//Save ourselves a trip through the loop below if there are no restricted fields
		if(restrictedFields == null || restrictedFields.isEmpty()){
			return;
		}
		
		if(existingRecord == null){
		    throw new DMLManagerException('DMLManager ERROR:  An existing record could not be found for object with Id = ' + obj.Id);
		}

		Map<String,Object> fieldsMap = getFieldMapFromExistingSObject(obj);
		
		// If any of the restricted values are present and have changed in the dml candidate object, throw an exception
		for(String fieldName : restrictedFields){
			if(fieldsMap.get(fieldName) != null && fieldsMap.get(fieldName) != existingRecord.get(fieldName) ){
				throw new FLSException(obj.getSObjectType(),obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),Operation.OP_UPDATE);
			}
		}	 
	}

	/**
	*@Description: Method to get existing records
	* 			   For update and upsert operations, retrieve a Map of all existing records, for each object that has an ID.
	* 			   objects without an Id are skipped, because there is no existing record in the database.
	*@param: objTypeMap
	*@return: Map<Id,SObject>
	*/
	private static Map<Id,SObject> getExistingRecords(Map<SObjectType,List<Id>> objTypeMap){
		Map<ID, SObject> result = new Map<Id,SObject>();

		Map<SObjectType,List<String>> operationRestrictedFields = cachedRestrictedFields.get(Operation.OP_UPDATE);
		
		for(SObjectType objType : objTypeMap.keySet()){
			List<String> restrictedFields = operationRestrictedFields.get(objType);
			
			if(restrictedFields == null || restrictedFields.isEmpty()){
				continue;
			}

			List<Id> seenIds = objTypeMap.get(objType);
			if(seenIds.isEmpty()){
				continue;
			}

			String fieldList = String.join(restrictedFields,',');
			result.putAll((Database.query('SELECT ' + fieldList + ' FROM ' + objType.getDescribe().getName() + ' WHERE Id IN :seenIds')));
		}
		
		return result;
	}
	
	/**
	*@Description: Method to Check CRUD permissions for the current user on the object
	*@param: objTypeList,dmlOperation
	*@return: void
	*/
	private static void checkCRUDPermission(Set<SObjectType> objTypeList, Operation dmlOperation){
		for(SObjectType objType : objTypeList){
			DescribeSObjectResult describeObject = objType.getDescribe();
			if((dmlOperation == Operation.OP_INSERT && !describeObject.isCreateable()) ||
				(dmlOperation == Operation.OP_UPDATE && !describeObject.isUpdateable()) ||
				(dmlOperation == Operation.OP_DELETE && !describeObject.isDeletable()) ||
				(dmlOperation == Operation.OP_UPSERT && !(describeObject.isCreateable() && describeObject.isUpdateable()))) {
				throw new CRUDException(objType,dmlOperation);
			}
		}
	}

	/**
	*@Description: Method to analyze the DML Collection List
	* 			   Get a Map of all the object types in the dml request and the list of fields for each 
	*              that the current user cannot update, based on FLS security settings
	*@param: objList,dmlOperation
	*@return: Map<SObjectType,List<Id>>
	*/
	private static Map<SObjectType,List<Id>> analyzeDMLCollection(List<SObject> objList, Operation dmlOperation){
		Map<SObjectType,List<Id>> result = new Map<SObjectType,List<Id>>();
		
		for(SObject obj : objList){
			ensureRestrictedFieldsEntry(obj, dmlOperation);
		
			List<Id> seenIds = result.get(obj.getSObjectType());
			if(seenIds == null){
				seenIds = new List<Id>();
				result.put(obj.getSObjectType(),seenIds);
			}
			
			if(obj.Id == null){
				continue;
			}	
			
			seenIds.add(obj.Id);
			
		}
		return result;
	}
	
	/**
	*@Description: Method to ensure Restricted Fields Entry
	*@param: obj,dmlOperation
	*@return: void
	*/
	private static void ensureRestrictedFieldsEntry(SObject obj, Operation dmlOperation){
		if(dmlOperation == Operation.OP_UPSERT){
			ensureRestrictedFields(obj,Operation.OP_INSERT);
			ensureRestrictedFields(obj,Operation.OP_UPDATE);
		}
		else{
			ensureRestrictedFields(obj,dmlOperation);
		}
	}
	
	/**
	*@Description: Method to ensure Restricted Fields
	*@param: obj,dmlOperation
	*@return: void
	*/
	private static void ensureRestrictedFields(SObject obj, Operation dmlOperation){
		Map<SObjectType,List<String>> operationRestrictedFields = cachedRestrictedFields.get(dmlOperation);
		if(operationRestrictedFields == null){
			operationRestrictedFields = new Map<SObjectType,List<String>>();
			cachedRestrictedFields.put(dmlOperation,operationRestrictedFields);
		}
		
		if(!operationRestrictedFields.containsKey(obj.getSObjectType())){

			DescribeSObjectResult describeObject = obj.getSObjectType().getDescribe();

			Map<String, Schema.SObjectField> objectFields = describeObject.fields.getMap();

			List<String> restrictedFields = new List<String>();

			for(String nm : objectFields.keyset()){
				if(!exceptionValues.contains(nm.toLowerCase())){
					DescribeFieldResult fr = objectFields.get(nm).getDescribe();
					if((!fr.isCalculated()) && ((dmlOperation == Operation.OP_INSERT && !fr.isCreateable()) ||
					   (dmlOperation == Operation.OP_UPDATE && !fr.isUpdateable())) 
					){
						restrictedFields.add(fr.getName());
					}  // there is not an isDeletable method at the field level
				}
			}
			operationRestrictedFields.put(obj.getSObjectType(),restrictedFields);
		}
	}	

}